using Microsoft.Extensions.Diagnostics.HealthChecks;

namespace VideoDashboard.Web.HealthChecks;

public class LivenessHealthCheck : IHealthCheck
{
    public Task<HealthCheckResult> CheckHealthAsync(
        HealthCheckContext context,
        CancellationToken cancellationToken = default)
    {
        string livenessProbeOverrideResult = MyEnvironmentVariables.LivenessProbeOverrideResult;
        if (!string.IsNullOrWhiteSpace(livenessProbeOverrideResult))
        {
            return livenessProbeOverrideResult.ToUpper() switch
            {
                "HEALTHY" => Task.FromResult(HealthCheckResult.Healthy()),
                "DEGRADED" => Task.FromResult(HealthCheckResult.Degraded()),
                _ => Task.FromResult(HealthCheckResult.Unhealthy()),
            };
        }

        // TODO
        // Add logic to determine the liveness of the application.

        return Task.FromResult(HealthCheckResult.Healthy());
    }
}

