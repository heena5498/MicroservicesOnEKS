using Microsoft.Extensions.Diagnostics.HealthChecks;

namespace VideoDashboard.Web.HealthChecks;

public class ReadinessHealthCheck : IHealthCheck
{
    public Task<HealthCheckResult> CheckHealthAsync(
        HealthCheckContext context,
        CancellationToken cancellationToken = default)
    {
        string readinessProbeOverrideResult = MyEnvironmentVariables.ReadinessProbeOverrideResult;
        if (!string.IsNullOrWhiteSpace(readinessProbeOverrideResult))
        {
            return readinessProbeOverrideResult.ToUpper() switch
            {
                "HEALTHY" => Task.FromResult(HealthCheckResult.Healthy()),
                "DEGRADED" => Task.FromResult(HealthCheckResult.Degraded()),
                _ => Task.FromResult(HealthCheckResult.Unhealthy()),
            };
        }

        // TODO
        // Add logic to determine the readiness of the application.

        return Task.FromResult(HealthCheckResult.Healthy());
    }
}
