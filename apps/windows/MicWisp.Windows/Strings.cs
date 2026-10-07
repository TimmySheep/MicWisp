using System.Globalization;
using Windows.Globalization;
using Windows.Storage;

namespace MicWisp.Windows;

internal static class Strings
{
    private static readonly Dictionary<string, (string En, string Zh)> Values = new()
    {
        ["ProductName"] = ("MicWisp", "MicWisp"),
        ["NavDashboard"] = ("Overview", "概览"), ["NavConnection"] = ("Connection", "连接"),
        ["NavAudio"] = ("Audio", "音频"), ["NavAbout"] = ("About", "关于"),
        ["Start"] = ("Start receiving", "启动接收服务"), ["Stop"] = ("Stop service", "停止服务"),
        ["Stopped"] = ("Stopped", "已停止"), ["Starting"] = ("Starting", "正在启动"),
        ["Running"] = ("Running", "运行中"), ["Failed"] = ("Needs attention", "需要处理"),
        ["ServiceTitle"] = ("Microphone service", "麦克风服务"),
        ["ConnectHint"] = ("Start the service, then connect a compatible phone on the selected network or USB mode.", "启动服务后，让兼容的手机通过所选网络或 USB 模式连接。"),
        ["Device"] = ("Connected device", "已连接设备"), ["NoDevice"] = ("No phone connected", "尚无手机连接"),
        ["Level"] = ("Input level", "输入电平"), ["Metrics"] = ("Network and audio metrics", "网络与音频指标"),
        ["Latency"] = ("Latency", "延迟"), ["NetworkLatency"] = ("Network latency", "网络延迟"),
        ["PhoneLatency"] = ("Phone-reported latency", "手机上报延迟"), ["Jitter"] = ("Jitter", "抖动"),
        ["Loss"] = ("Packet loss", "丢包率"), ["Buffer"] = ("Buffer", "缓冲区"),
        ["Bitrate"] = ("Bitrate", "码率"), ["SampleRate"] = ("Sample rate", "采样率"),
        ["WebClients"] = ("Web clients", "Web 客户端"), ["Muted"] = ("Muted", "静音"),
        ["Monitoring"] = ("Listen locally", "本机监听"), ["Spectrum"] = ("Audio spectrum", "音频频谱"),
        ["ConnectionTitle"] = ("Connection settings", "连接设置"), ["Mode"] = ("Mode", "模式"),
        ["Wifi"] = ("Wi-Fi", "Wi-Fi"), ["Usb"] = ("USB (ADB)", "USB（ADB）"), ["Web"] = ("Web", "Web"),
        ["Port"] = ("Audio port (TCP; UDP uses the next port)", "音频端口（TCP；UDP 使用相邻端口）"),
        ["WebPort"] = ("Web port", "Web 端口"), ["BindAddress"] = ("Manual listen IP", "手动监听 IP"),
        ["AutoBind"] = ("Listen on all interfaces", "监听所有网络接口"),
        ["OutputDevice"] = ("Virtual microphone output", "虚拟麦克风输出设备"),
        ["OutputHint"] = ("Select the backend output device. Install VB-CABLE separately if it is not available.", "选择后端输出设备。若未检测到 VB-CABLE，请单独安装。"),
        ["MuteSync"] = ("Synchronize mute with phone", "与手机同步静音状态"),
        ["RestartHint"] = ("Connection changes require a service restart.", "连接设置变更需要重启服务。"),
        ["Discovery"] = ("Nearby services", "附近服务"),
        ["DiscoveryHint"] = ("mDNS discovery is informational; this app runs the desktop receiver.", "mDNS 发现仅供参考；本应用运行的是桌面接收端。"),
        ["LocalAddresses"] = ("Local addresses for phone setup", "提供给手机端填写的本机地址"),
        ["NoAddresses"] = ("No active non-loopback IPv4 address found.", "未检测到活动的非回环 IPv4 地址。"),
        ["UsbHint"] = ("Enable USB debugging and connect the phone. The backend configures ADB reverse when the service starts.", "请启用 USB 调试并连接手机；服务启动时后端会配置 ADB reverse。"),
        ["WebHint"] = ("Web mode serves audio to browser clients over HTTPS.", "Web 模式通过 HTTPS 向浏览器客户端提供音频。"),
        ["VirtualStatus"] = ("Virtual audio device status", "虚拟音频设备状态"),
        ["Available"] = ("Available", "已检测到"), ["NotDetected"] = ("Not detected", "未检测到"),
        ["Setup"] = ("Setup instructions", "查看安装说明"), ["Apply"] = ("Save and apply", "保存并应用"),
        ["DefaultOutput"] = ("System default output", "系统默认输出设备"),
        ["AudioTitle"] = ("Audio processing", "音频处理"), ["Gain"] = ("Amplification (dB)", "放大（dB）"),
        ["Noise"] = ("Noise suppression", "噪声抑制"), ["NoiseType"] = ("Noise suppression engine", "降噪引擎"),
        ["Intensity"] = ("Suppression intensity", "降噪强度"), ["Aec"] = ("Acoustic echo cancellation (AEC)", "声学回声消除（AEC）"),
        ["Dereverb"] = ("Dereverberation", "去混响"), ["DereverbLevel"] = ("Dereverberation level", "去混响强度"),
        ["Equalizer"] = ("Equalizer", "均衡器"), ["Preamp"] = ("Equalizer preamp", "均衡器前置增益"),
        ["Agc"] = ("Automatic gain control (AGC)", "自动增益控制（AGC）"), ["AgcTarget"] = ("AGC target", "AGC 目标值"),
        ["AgcAttack"] = ("AGC attack", "AGC 起效速度"), ["AgcDecay"] = ("AGC decay", "AGC 衰减速度"),
        ["Vad"] = ("Voice activity detection (VAD)", "语音活动检测（VAD）"),
        ["VadThreshold"] = ("VAD threshold (dB)", "VAD 阈值（dB）"), ["OutputBuffer"] = ("Output buffer (ms)", "输出缓冲区（毫秒）"),
        ["Chain"] = ("Processing order", "处理顺序"), ["MoveUp"] = ("Move up", "上移"), ["MoveDown"] = ("Move down", "下移"),
        ["DspApplied"] = ("DSP changes apply to the running service.", "DSP 修改会应用到正在运行的服务。"),
        ["AboutTitle"] = ("About this application", "关于本应用"), ["Version"] = ("Version", "版本"),
        ["IndependentNotice"] = ("This is an independent third-party client compatible with the MicYou protocol. It is developed independently by TimmySheep and is not affiliated with, sponsored, or endorsed by MicYou or its author LanRhyme. “MicYou” is LanRhyme’s project name and is used only to describe compatibility.", "本项目是兼容 MicYou 协议的第三方独立客户端，由 TimmySheep 独立开发，与 MicYou 项目及其作者 LanRhyme 无隶属关系，未获其赞助或背书。“MicYou”为 LanRhyme 的项目名称，此处仅用于说明兼容性。"),
        ["LicenseNotice"] = ("Licensed under GPL-3.0. This application is provided without warranty. You may redistribute it under the license terms. The complete license texts are included with this application.", "本应用以 GPL-3.0 许可发布，不提供任何担保。您可按许可证条款再分发。应用附有完整许可文本。"),
        ["OpenGPL"] = ("Open GPL-3.0 license", "打开 GPL-3.0 许可"), ["OpenUpstream"] = ("Upstream license and plugin exception", "上游许可与插件例外"),
        ["Settings"] = ("Preferences", "偏好设置"), ["Language"] = ("Language", "语言"),
        ["System"] = ("System default", "跟随系统"), ["English"] = ("English", "English"),
        ["Chinese"] = ("简体中文", "简体中文"), ["LaunchAtLogin"] = ("Launch at login", "登录时启动"),
        ["ExplicitStart"] = ("The microphone service starts only after you explicitly choose Start. Launching at login never opens the microphone service.", "麦克风服务仅会在您明确点击“启动”后开始。登录时启动应用不会自动启动麦克风服务。"),
        ["TrayShow"] = ("Open MicWisp", "打开 MicWisp"), ["TrayQuit"] = ("Quit", "退出"),
        ["NoServices"] = ("No compatible services discovered.", "未发现兼容服务。"),
        ["NoAdb"] = ("No ADB device detected.", "未检测到 ADB 设备。"),
        ["RestartRequired"] = ("Connection settings were saved. Restart the service to apply them.", "连接设置已保存；重启服务后生效。"),
    };

    private static string? _override;
    public static event Action? LanguageChanged;

    static Strings()
    {
        var saved = ApplicationData.Current.LocalSettings.Values["language"] as string;
        _override = saved switch
        {
            "zh" => "zh-CN",
            "en" => "en-US",
            _ => null,
        };
        ApplicationLanguages.PrimaryLanguageOverride = _override ?? string.Empty;
    }

    public static bool IsChinese
    {
        get
        {
            var language = _override ?? CultureInfo.CurrentUICulture.Name;
            return language.StartsWith("zh", StringComparison.OrdinalIgnoreCase);
        }
    }

    public static string Get(string key) => Values.TryGetValue(key, out var pair)
        ? (IsChinese ? pair.Zh : pair.En)
        : key;

    public static void SetLanguage(string value)
    {
        _override = value switch { "zh" => "zh-CN", "en" => "en-US", _ => null };
        ApplicationData.Current.LocalSettings.Values["language"] = value;
        ApplicationLanguages.PrimaryLanguageOverride = _override ?? string.Empty;
        LanguageChanged?.Invoke();
    }
}
