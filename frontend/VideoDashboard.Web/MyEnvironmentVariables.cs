namespace VideoDashboard.Web;

public static class MyEnvironmentVariables
{
    public static string LivenessProbeOverrideResult
        => GetVariable("VIDEO_DASHBOARD_DEBUG_LIVENESS_PROBE_OVERRIDE_RESULT");

    public static string ReadinessProbeOverrideResult
        => GetVariable("VIDEO_DASHBOARD_DEBUG_READINESS_PROBE_OVERRIDE_RESULT");

    private static string GetVariable(string variable) => Environment.GetEnvironmentVariable(variable) ?? "";
}
