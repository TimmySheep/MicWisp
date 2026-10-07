using System.Text.Json.Serialization;

namespace MicWisp.Windows;

internal sealed class ServerPreferences
{
    public ushort Port { get; set; } = 8554;
    public ushort WebPort { get; set; } = 8443;
    public string Mode { get; set; } = "wifi";
    public string BindAddress { get; set; } = "0.0.0.0";
    public bool AutoBind { get; set; } = true;
    public string OutputDevice { get; set; } = "";
    public bool MuteSync { get; set; } = true;
}

internal sealed class EqualizerSettings
{
    public bool Enabled { get; set; }
    public float PreAmp { get; set; }
    public List<float> Gains { get; set; } = Enumerable.Repeat(0f, 10).ToList();
}

internal sealed class DspSettings
{
    public float Gain { get; set; }
    public bool NsEnabled { get; set; }
    public string NsType { get; set; } = "PureVox";
    public float NsIntensity { get; set; } = 50;
    public bool DereverbEnabled { get; set; }
    public float DereverbLevel { get; set; } = 50;
    public bool AgcEnabled { get; set; }
    public float AgcTarget { get; set; } = 16000;
    public float AgcAttack { get; set; } = 50;
    public float AgcDecay { get; set; } = 50;
    public bool VadEnabled { get; set; }
    public float VadThreshold { get; set; } = -40;
    public bool AecEnabled { get; set; }
    public uint OutputBufferMs { get; set; } = 300;
    public List<string> ProcessingChain { get; set; } = ["AEC", "NoiseReduction", "Dereverb", "Equalizer", "Amplifier", "AGC", "VAD"];
    public EqualizerSettings Equalizer { get; set; } = new();
}

internal sealed class AudioMetrics
{
    public int Bitrate { get; set; }
    public int SampleRate { get; set; }
    public long LatencyMs { get; set; }
    public long NetworkLatencyMs { get; set; }
    public double PacketLossRate { get; set; }
    public double JitterMs { get; set; }
    public long BufferDurationMs { get; set; }
}

internal sealed class ConnectedDevice
{
    public string Name { get; set; } = "";
    public string Ip { get; set; } = "";
    public uint Latency { get; set; }
}
