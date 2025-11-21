using Microsoft.Extensions.Diagnostics.HealthChecks;
using VideoDashboard.Interfaces;

namespace VideoDashboard.Web.HealthChecks;

public class ReadinessHealthCheck(IMediaService mediaService, IAnalyticsService analyticsService) : IHealthCheck
{
    private readonly IMediaService _mediaService = mediaService;
    private readonly IAnalyticsService _analyticsService = analyticsService;

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

        if (_mediaService.IsServiceReady && _analyticsService.IsServiceReady)
        {
            return Task.FromResult(HealthCheckResult.Healthy());
        }
        else
        {
            return Task.FromResult(HealthCheckResult.Unhealthy());
        }
    }
}
