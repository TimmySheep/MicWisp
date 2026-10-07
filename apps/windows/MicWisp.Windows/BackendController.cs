using System.Collections.Concurrent;
using System.ComponentModel;
using System.Diagnostics;
using System.Net;
using System.Net.Sockets;
using System.Runtime.CompilerServices;
using System.Text;
using System.Text.Json;
using Microsoft.UI.Dispatching;

namespace MicWisp.Windows;

internal sealed class BackendController : INotifyPropertyChanged, IDisposable
{
    private const int MaxLineLength = 64 * 1024;
    private static readonly JsonSerializerOptions JsonOptions = new(JsonSerializerDefaults.Web) { WriteIndented = true };
    private readonly ConcurrentDictionary<string, TaskCompletionSource<JsonElement>> _pending = new();
    private readonly SemaphoreSlim _stdinGate = new(1, 1);
    private Process? _process;
    private DispatcherQueue? _dispatcher;
    private TaskCompletionSource<bool>? _ready;
    private CancellationTokenSource? _dspDebounce;
    private string _phase = "Stopped";
    private string? _error;
    private string? _diagnostic;
    private bool _isReady;
    private bool _isMuted;
    private bool _isMonitoring;
    private uint _audioLevel;
    private int _audioPeak = 1;
    private int _webClientCount;
    private double _packetLoss;
    private double _jitter;
    private long _latency;
    private long _networkLatency;
    private long _bufferDuration;
    private int _bitrate;
    private int _sampleRate;
    private ConnectedDevice? _device;
    private bool? _virtualAudioInstalled;
    private string? _virtualAudioUrl;
    private IReadOnlyList<string> _audioDevices = Array.Empty<string>();
    private IReadOnlyList<string> _adbDevices = Array.Empty<string>();
    private IReadOnlyList<string> _discoveredServices = Array.Empty<string>();
    private IReadOnlyList<string> _localAddresses = Array.Empty<string>();

    public event PropertyChangedEventHandler? PropertyChanged;

    public string Phase { get => _phase; private set { _phase = value; Changed(); Changed(nameof(PhaseText)); } }
    public string? Error { get => _error; private set { _error = value; Changed(); } }
    public string? Diagnostic { get => _diagnostic; private set { _diagnostic = value; Changed(); } }
    public bool IsReady { get => _isReady; private set { _isReady = value; Changed(); Changed(nameof(CanStop)); } }
    public bool CanStop => _process is { HasExited: false };
    public bool IsMuted { get => _isMuted; private set { _isMuted = value; Changed(); } }
    public bool IsMonitoring { get => _isMonitoring; private set { _isMonitoring = value; Changed(); } }
    public uint AudioLevel { get => _audioLevel; private set { _audioLevel = value; Changed(); Changed(nameof(AudioFraction)); } }
    public double AudioFraction => Math.Clamp((double)AudioLevel / Math.Max(_audioPeak, 1), 0, 1);
    public int WebClientCount { get => _webClientCount; private set { _webClientCount = value; Changed(); } }
    public double PacketLoss { get => _packetLoss; private set { _packetLoss = value; Changed(); } }
    public double Jitter { get => _jitter; private set { _jitter = value; Changed(); } }
    public long Latency { get => _latency; private set { _latency = value; Changed(); } }
    public long NetworkLatency { get => _networkLatency; private set { _networkLatency = value; Changed(); } }
    public long BufferDuration { get => _bufferDuration; private set { _bufferDuration = value; Changed(); } }
    public int Bitrate { get => _bitrate; private set { _bitrate = value; Changed(); } }
    public int SampleRate { get => _sampleRate; private set { _sampleRate = value; Changed(); } }
    public ConnectedDevice? Device { get => _device; private set { _device = value; Changed(); } }
    public bool? VirtualAudioInstalled { get => _virtualAudioInstalled; private set { _virtualAudioInstalled = value; Changed(); } }
    public string? VirtualAudioUrl { get => _virtualAudioUrl; private set { _virtualAudioUrl = value; Changed(); } }
    public IReadOnlyList<string> AudioDevices { get => _audioDevices; private set { _audioDevices = value; Changed(); } }
    public IReadOnlyList<string> AdbDevices { get => _adbDevices; private set { _adbDevices = value; Changed(); } }
    public IReadOnlyList<string> DiscoveredServices { get => _discoveredServices; private set { _discoveredServices = value; Changed(); } }
    public IReadOnlyList<string> LocalAddresses { get => _localAddresses; private set { _localAddresses = value; Changed(); } }
    public string PhaseText => Phase switch
    {
        "Starting" => Strings.Get("Starting"),
        "Running" => Strings.Get("Running"),
        "Failed" => Strings.Get("Failed"),
        _ => Strings.Get("Stopped"),
    };

    public ServerPreferences Connection { get; private set; } = new();
    public DspSettings Dsp { get; private set; } = new();

    public void AttachDispatcher(DispatcherQueue dispatcher)
    {
        _dispatcher = dispatcher;
        LoadConfiguration();
        LocalAddresses = GetLocalIPv4Addresses();
    }

    public async Task StartAsync()
    {
        if (CanStop) return;
        try
        {
            LoadConfiguration();
            SaveJson(ConfigPath("server.json"), Connection);
            SaveJson(ConfigPath("settings.json"), Dsp);
            var executable = LocateBackend();
            if (executable is null)
                throw new InvalidOperationException("The patched micyou-cli sidecar was not found. Follow apps/windows/README.md to build and install it.");

            var startInfo = new ProcessStartInfo(executable)
            {
                WorkingDirectory = Path.GetDirectoryName(executable)!,
                UseShellExecute = false,
                RedirectStandardInput = true,
                RedirectStandardOutput = true,
                RedirectStandardError = true,
                CreateNoWindow = true,
            };
            startInfo.ArgumentList.Add("serve");
            startInfo.ArgumentList.Add("--jsonl");
            var child = new Process { StartInfo = startInfo, EnableRaisingEvents = true };
            child.Exited += (_, _) => Dispatch(() => ProcessExited(child.ExitCode));
            if (!child.Start()) throw new InvalidOperationException("The micyou-cli process could not be started.");
            _process = child;
            _ready = new TaskCompletionSource<bool>(TaskCreationOptions.RunContinuationsAsynchronously);
            IsReady = false;
            Error = null;
            Phase = "Starting";
            _ = ReadFramesAsync(child.StandardOutput, HandleFrameAsync, child);
            _ = ReadFramesAsync(child.StandardError, HandleDiagnosticAsync, child);
            await _ready.Task.WaitAsync(TimeSpan.FromSeconds(30));
        }
        catch (Exception ex)
        {
            Error = ex is TimeoutException ? "The backend did not become ready within 30 seconds." : ex.Message;
            Phase = "Failed";
            if (CanStop) await StopAsync();
        }
    }

    public async Task StopAsync()
    {
        var child = _process;
        if (child is null || child.HasExited)
        {
            ResetState();
            return;
        }

        if (IsReady)
        {
            try { _ = await RequestAsync("stop", timeout: TimeSpan.FromSeconds(5)); }
            catch (Exception ex) { Diagnostic = ex.Message; }
        }
        else
        {
            try { child.StandardInput.Close(); } catch { }
        }

        try { await child.WaitForExitAsync().WaitAsync(TimeSpan.FromSeconds(8)); }
        catch (TimeoutException)
        {
            try { child.Kill(entireProcessTree: false); } catch { }
            try { await child.WaitForExitAsync().WaitAsync(TimeSpan.FromSeconds(3)); } catch { }
        }
        if (child.HasExited) ResetState();
    }

    public async Task ApplyConnectionAsync(ServerPreferences updated)
    {
        Connection = updated;
        SaveJson(ConfigPath("server.json"), Connection);
        LocalAddresses = GetLocalIPv4Addresses();
        if (IsReady)
        {
            _ = await RequestAsync("applyConnectionSettings", Connection);
            await StopAsync();
            await StartAsync();
        }
    }

    public void UpdateDsp(DspSettings updated)
    {
        Dsp = updated;
        Changed(nameof(Dsp));
        _dspDebounce?.Cancel();
        _dspDebounce?.Dispose();
        _dspDebounce = new CancellationTokenSource();
        var token = _dspDebounce.Token;
        _ = ApplyDspAfterDelayAsync(token);
    }

    private async Task ApplyDspAfterDelayAsync(CancellationToken token)
    {
        try
        {
            await Task.Delay(250, token);
            SaveJson(ConfigPath("settings.json"), Dsp);
            if (IsReady) _ = await RequestAsync("applyDspSettings", Dsp);
        }
        catch (OperationCanceledException) { }
        catch (Exception ex) { Dispatch(() => Error = ex.Message); }
    }

    public async Task SetMutedAsync(bool value)
    {
        if (!IsReady) return;
        await RequestAsync("setMuted", new { isMuted = value });
        IsMuted = value;
    }

    public async Task SetMonitoringAsync(bool value)
    {
        if (!IsReady) return;
        await RequestAsync("setMonitoring", new { enabled = value });
        IsMonitoring = value;
    }

    public async Task SetSpectrumAsync(bool enabled)
    {
        if (IsReady) await RequestAsync("setSpectrumStreaming", new { enabled });
    }

    public async Task RefreshAsync()
    {
        if (!IsReady) return;
        var dspJson = await RequestAsync("getDspSettings");
        Dsp = JsonSerializer.Deserialize<DspSettings>(dspJson, JsonOptions) ?? new();
        Changed(nameof(Dsp));
        var connectionJson = await RequestAsync("getConnectionSettings");
        Connection = JsonSerializer.Deserialize<ServerPreferences>(connectionJson, JsonOptions) ?? new();
        Changed(nameof(Connection));
        var devices = await RequestAsync("listAudioDevices");
        AudioDevices = ReadStringArray(devices, "devices");
        var adb = await RequestAsync("listAdbDevices");
        AdbDevices = ReadObjectStringArray(adb, "devices", "serial", "state");
        var virtualStatus = await RequestAsync("getVirtualAudioStatus");
        if (virtualStatus.TryGetProperty("installed", out var installed)) VirtualAudioInstalled = installed.GetBoolean();
        if (virtualStatus.TryGetProperty("manualSetupUrl", out var url) && url.ValueKind == JsonValueKind.String) VirtualAudioUrl = url.GetString();
        LocalAddresses = GetLocalIPv4Addresses();
    }

    public async Task SetLaunchAtLoginAsync(bool enabled)
    {
        var task = await Windows.ApplicationModel.StartupTask.GetAsync("MicWispStartup");
        if (enabled)
        {
            var state = await task.RequestEnableAsync();
            if (state is not (Windows.ApplicationModel.StartupTaskState.Enabled or Windows.ApplicationModel.StartupTaskState.EnabledByPolicy))
                throw new InvalidOperationException("Windows did not enable this startup task.");
        }
        else
        {
            task.Disable();
        }
    }

    public void SetDiscoveredServices(IReadOnlyList<string> services) => DiscoveredServices = services;

    public void ShowError(string message) => Error = message;

    public static async Task<IReadOnlyList<string>> BrowseMdnsAsync(CancellationToken cancellationToken)
    {
        var services = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        foreach (var type in new[] { "_micyou._tcp.local", "_micyou-web._tcp.local" })
        {
            try
            {
                using var udp = new UdpClient(AddressFamily.InterNetwork);
                udp.Client.SetSocketOption(SocketOptionLevel.Socket, SocketOptionName.ReuseAddress, true);
                udp.Client.Bind(new IPEndPoint(IPAddress.Any, 5353));
                udp.JoinMulticastGroup(IPAddress.Parse("224.0.0.251"));
                var query = BuildMdnsQuery(type);
                await udp.SendAsync(query, new IPEndPoint(IPAddress.Parse("224.0.0.251"), 5353), cancellationToken);
                var end = DateTime.UtcNow.AddSeconds(2);
                while (DateTime.UtcNow < end && !cancellationToken.IsCancellationRequested)
                {
                    using var receiveTimeout = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
                    receiveTimeout.CancelAfter(TimeSpan.FromMilliseconds(250));
                    try
                    {
                        var result = await udp.ReceiveAsync(receiveTimeout.Token);
                        foreach (var item in ParseMdnsInstances(result.Buffer, type)) services.Add(item);
                    }
                    catch (OperationCanceledException) when (!cancellationToken.IsCancellationRequested) { }
                }
            }
            catch (OperationCanceledException) { throw; }
            catch (SocketException) { }
        }
        return services.Order(StringComparer.OrdinalIgnoreCase).ToArray();
    }

    private async Task<JsonElement> RequestAsync(string name, object? payload = null, TimeSpan? timeout = null)
    {
        var child = _process;
        if (!IsReady && name != "stop") throw new InvalidOperationException("The backend is not ready.");
        if (child is null || child.HasExited) throw new InvalidOperationException("The backend control pipe is closed.");
        var id = Guid.NewGuid().ToString("N");
        var pending = new TaskCompletionSource<JsonElement>(TaskCreationOptions.RunContinuationsAsynchronously);
        if (!_pending.TryAdd(id, pending)) throw new InvalidOperationException("Could not allocate a backend request ID.");
        try
        {
            await _stdinGate.WaitAsync();
            try
            {
                var line = JsonSerializer.Serialize(new { v = 1, type = "command", id, name, payload = payload ?? new { } }, JsonOptions);
                await child.StandardInput.WriteLineAsync(line);
                await child.StandardInput.FlushAsync();
            }
            finally { _stdinGate.Release(); }
            return await pending.Task.WaitAsync(timeout ?? TimeSpan.FromSeconds(10));
        }
        finally { _pending.TryRemove(id, out _); }
    }

    private async Task ReadFramesAsync(StreamReader reader, Action<string> callback, Process child)
    {
        var chunk = new char[4096];
        var line = new StringBuilder();
        try
        {
            while (true)
            {
                var count = await reader.ReadAsync(chunk.AsMemory());
                if (count == 0) break;
                for (var i = 0; i < count; i++)
                {
                    var ch = chunk[i];
                    if (ch == '\n')
                    {
                        if (line.Length > 0 && line[^1] == '\r') line.Length--;
                        callback(line.ToString());
                        line.Clear();
                    }
                    else
                    {
                        if (line.Length >= MaxLineLength) throw new InvalidDataException("The backend emitted a line larger than 64 KiB.");
                        line.Append(ch);
                    }
                }
            }
            if (line.Length > 0) callback(line.ToString());
        }
        catch (Exception ex)
        {
            if (ReferenceEquals(reader, child.StandardOutput)) Dispatch(() => FailProtocol(ex.Message));
            else Dispatch(() => Diagnostic = ex.Message);
        }
    }

    private void HandleFrameAsync(string line)
    {
        try
        {
            using var document = JsonDocument.Parse(line);
            var root = document.RootElement;
            if (!root.TryGetProperty("v", out var version) || version.GetInt32() != 1 || !root.TryGetProperty("type", out var kind))
                throw new InvalidDataException("Unsupported backend protocol frame.");
            switch (kind.GetString())
            {
                case "ready":
                    IsReady = true;
                    Phase = "Running";
                    _ready?.TrySetResult(true);
                    break;
                case "error":
                    Error = ReadMessage(root, "error");
                    Phase = "Failed";
                    _ready?.TrySetException(new InvalidOperationException(Error));
                    break;
                case "response":
                    var id = root.GetProperty("id").GetString();
                    if (id is null || !_pending.TryRemove(id, out var source)) break;
                    if (root.GetProperty("ok").GetBoolean())
                    {
                        if (root.TryGetProperty("payload", out var payload)) source.TrySetResult(payload.Clone());
                        else
                        {
                            using var empty = JsonDocument.Parse("{}");
                            source.TrySetResult(empty.RootElement.Clone());
                        }
                    }
                    else source.TrySetException(new InvalidOperationException(ReadMessage(root, "error")));
                    break;
                case "event":
                    HandleEvent(root.GetProperty("name").GetString() ?? "", root.GetProperty("payload"));
                    break;
                default:
                    throw new InvalidDataException("Unknown backend frame type.");
            }
        }
        catch (Exception ex) { FailProtocol(ex.Message); }
    }

    private void HandleDiagnosticAsync(string line)
    {
        if (!string.IsNullOrWhiteSpace(line)) Diagnostic = line;
    }

    private void HandleEvent(string name, JsonElement payload)
    {
        switch (name)
        {
            case "device_connected":
                Device = new ConnectedDevice { Name = GetString(payload, "name"), Ip = GetString(payload, "ip"), Latency = GetUInt(payload, "latency") };
                break;
            case "device_disconnected": Device = null; break;
            case "audio_metrics":
                Bitrate = GetInt(payload, "bitrate"); SampleRate = GetInt(payload, "sampleRate");
                Latency = GetLong(payload, "latencyMs"); NetworkLatency = GetLong(payload, "networkLatencyMs");
                PacketLoss = GetDouble(payload, "packetLossRate"); Jitter = GetDouble(payload, "jitterMs");
                BufferDuration = GetLong(payload, "bufferDurationMs");
                break;
            case "audio_level":
                AudioLevel = GetUInt(payload, "level");
                _audioPeak = Math.Max(_audioPeak, checked((int)Math.Min(AudioLevel, int.MaxValue)));
                Changed(nameof(AudioFraction));
                break;
            case "mute_state_changed": IsMuted = GetBool(payload, "isMuted"); break;
            case "monitoring_state_changed": IsMonitoring = GetBool(payload, "enabled"); break;
            case "web_client_count": WebClientCount = GetInt(payload, "count"); break;
            case "udp_audio_warning": Diagnostic = "UDP audio packets are not arriving. Check the local network and firewall."; break;
            case "aec_status_changed":
                if (!GetBool(payload, "available")) Diagnostic = $"AEC unavailable: {GetString(payload, "reason")}";
                break;
            case "install_progress": Diagnostic = GetString(payload, "message"); break;
            case "server_stopped": IsReady = false; Device = null; break;
            case "audio_spectrum": Changed(nameof(Diagnostic)); break;
        }
    }

    private void ProcessExited(int exitCode)
    {
        ResetState();
        if (exitCode != 0 && Phase != "Failed")
        {
            Error = $"Backend exited with status {exitCode}.";
            Phase = "Failed";
        }
    }

    private void FailProtocol(string message)
    {
        Error = message;
        Phase = "Failed";
        IsReady = false;
        try { _process?.StandardInput.Close(); } catch { }
    }

    private void ResetState()
    {
        IsReady = false;
        Device = null;
        AudioLevel = 0;
        _audioPeak = 1;
        WebClientCount = 0;
        IsMuted = false;
        IsMonitoring = false;
        _process?.Dispose();
        _process = null;
        Changed(nameof(CanStop));
        foreach (var item in _pending.Values) item.TrySetException(new IOException("Backend process exited."));
        _pending.Clear();
        if (Phase != "Failed") Phase = "Stopped";
    }

    private static string? LocateBackend()
    {
        var candidates = new List<string>
        {
            Path.Combine(AppContext.BaseDirectory, "Helpers", "micyou-cli.exe"),
            Path.Combine(AppContext.BaseDirectory, "micyou-cli.exe"),
        };
        var path = Environment.GetEnvironmentVariable("PATH") ?? "";
        candidates.AddRange(path.Split(Path.PathSeparator, StringSplitOptions.RemoveEmptyEntries)
            .Select(folder => Path.Combine(folder, "micyou-cli.exe")));
        return candidates.FirstOrDefault(File.Exists);
    }

    private static string ConfigPath(string file) => Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), "micyou", file);

    private void LoadConfiguration()
    {
        Connection = LoadJson<ServerPreferences>(ConfigPath("server.json")) ?? Connection;
        Dsp = LoadJson<DspSettings>(ConfigPath("settings.json")) ?? Dsp;
        Changed(nameof(Connection)); Changed(nameof(Dsp));
    }

    private static T? LoadJson<T>(string path)
    {
        try { return File.Exists(path) ? JsonSerializer.Deserialize<T>(File.ReadAllText(path), JsonOptions) : default; }
        catch { return default; }
    }

    private static void SaveJson<T>(string path, T data)
    {
        Directory.CreateDirectory(Path.GetDirectoryName(path)!);
        File.WriteAllText(path, JsonSerializer.Serialize(data, JsonOptions));
    }

    private static IReadOnlyList<string> GetLocalIPv4Addresses() =>
        Dns.GetHostAddresses(Dns.GetHostName())
            .Where(address => address.AddressFamily == AddressFamily.InterNetwork && !IPAddress.IsLoopback(address))
            .Select(address => address.ToString()).Distinct().Order(StringComparer.OrdinalIgnoreCase).ToArray();

    private static byte[] BuildMdnsQuery(string service)
    {
        using var stream = new MemoryStream();
        using var writer = new BinaryWriter(stream, Encoding.ASCII, leaveOpen: true);
        writer.Write(new byte[2]); writer.Write((byte)0); writer.Write((byte)0); writer.Write((byte)0); writer.Write((byte)1);
        writer.Write(new byte[6]);
        foreach (var label in service.Split('.'))
        {
            var bytes = Encoding.ASCII.GetBytes(label);
            writer.Write((byte)bytes.Length); writer.Write(bytes);
        }
        writer.Write((byte)0); writer.Write((byte)0); writer.Write((byte)12); writer.Write((byte)0); writer.Write((byte)1);
        return stream.ToArray();
    }

    private static IEnumerable<string> ParseMdnsInstances(byte[] packet, string serviceType)
    {
        if (packet.Length < 12) yield break;
        var questions = ReadU16(packet, 4);
        var answers = ReadU16(packet, 6) + ReadU16(packet, 8) + ReadU16(packet, 10);
        var offset = 12;
        for (var i = 0; i < questions; i++)
        {
            if (offset >= packet.Length) yield break;
            _ = ReadDnsName(packet, ref offset);
            if (offset + 4 > packet.Length) yield break;
            offset += 4;
        }
        for (var i = 0; i < answers && offset + 10 <= packet.Length; i++)
        {
            var owner = ReadDnsName(packet, ref offset);
            var type = ReadU16(packet, offset); var dataLength = ReadU16(packet, offset + 8); offset += 10;
            if (offset + dataLength > packet.Length) yield break;
            if (type == 12 && dataLength > 0)
            {
                var dataOffset = offset;
                var target = ReadDnsName(packet, ref dataOffset);
                if (owner.Equals(serviceType, StringComparison.OrdinalIgnoreCase)) yield return target;
            }
            offset += dataLength;
        }
    }

    private static string ReadDnsName(byte[] packet, ref int offset)
    {
        var labels = new List<string>();
        var cursor = offset;
        var jumped = false;
        var guard = 0;
        while (cursor < packet.Length && guard++ < 128)
        {
            var length = packet[cursor++];
            if (length == 0) { if (!jumped) offset = cursor; break; }
            if ((length & 0xC0) == 0xC0)
            {
                if (cursor >= packet.Length) break;
                var pointer = ((length & 0x3F) << 8) | packet[cursor++];
                if (!jumped) offset = cursor;
                cursor = pointer;
                jumped = true;
                continue;
            }
            if (cursor + length > packet.Length) break;
            labels.Add(Encoding.UTF8.GetString(packet, cursor, length));
            cursor += length;
        }
        return string.Join('.', labels);
    }

    private static ushort ReadU16(byte[] data, int offset) => (ushort)((data[offset] << 8) | data[offset + 1]);
    private static string GetString(JsonElement value, string key) => value.TryGetProperty(key, out var item) && item.ValueKind == JsonValueKind.String ? item.GetString() ?? "" : "";
    private static int GetInt(JsonElement value, string key) => value.TryGetProperty(key, out var item) && item.TryGetInt32(out var result) ? result : 0;
    private static long GetLong(JsonElement value, string key) => value.TryGetProperty(key, out var item) && item.TryGetInt64(out var result) ? result : 0;
    private static uint GetUInt(JsonElement value, string key) => value.TryGetProperty(key, out var item) && item.TryGetUInt32(out var result) ? result : 0;
    private static double GetDouble(JsonElement value, string key) => value.TryGetProperty(key, out var item) && item.TryGetDouble(out var result) ? result : 0;
    private static bool GetBool(JsonElement value, string key) => value.TryGetProperty(key, out var item) && item.ValueKind == JsonValueKind.True;
    private static string ReadMessage(JsonElement root, string key) => root.TryGetProperty(key, out var error) && error.TryGetProperty("message", out var message) ? message.GetString() ?? "Backend operation failed." : "Backend operation failed.";

    private static IReadOnlyList<string> ReadStringArray(JsonElement root, string property) =>
        root.TryGetProperty(property, out var array) && array.ValueKind == JsonValueKind.Array
            ? array.EnumerateArray().Where(item => item.ValueKind == JsonValueKind.String).Select(item => item.GetString() ?? "").ToArray()
            : Array.Empty<string>();

    private static IReadOnlyList<string> ReadObjectStringArray(JsonElement root, string property, string field, string state) =>
        root.TryGetProperty(property, out var array) && array.ValueKind == JsonValueKind.Array
            ? array.EnumerateArray().Select(item => $"{GetString(item, field)} ({GetString(item, state)})").ToArray()
            : Array.Empty<string>();

    private void Dispatch(Action action)
    {
        if (_dispatcher is null || _dispatcher.HasThreadAccess) action();
        else _dispatcher.TryEnqueue(() => action());
    }

    private void Changed([CallerMemberName] string? property = null) => PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(property));

    public void Dispose()
    {
        _dspDebounce?.Cancel(); _dspDebounce?.Dispose();
        _stdinGate.Dispose();
        _process?.Dispose();
    }
}
