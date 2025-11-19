using Microsoft.Extensions.Diagnostics.HealthChecks;
using VideoDashboard.Web.HealthChecks;

WebApplicationBuilder builder = WebApplication.CreateBuilder(args);

// Add services to the application.

builder.Services.AddHealthChecks()
    .AddCheck<LivenessHealthCheck>(
        name: nameof(LivenessHealthCheck),
        tags: ["liveness"])
    .AddCheck<ReadinessHealthCheck>(
        name: nameof(ReadinessHealthCheck),
        tags: ["readiness"]);

builder.Services.AddControllersWithViews();

WebApplication app = builder.Build();

// Configure the HTTP request pipeline.

if (!app.Environment.IsDevelopment())
{
    app.UseExceptionHandler("/Home/Error");

    // The default HSTS value is 30 days. You may want to change this for
    // production scenarios, see https://aka.ms/aspnetcore-hsts.
    app.UseHsts();
}

app.UseHttpsRedirection();

app.UseRouting();

app.UseAuthorization();

app.MapStaticAssets();

app.MapHealthChecks("/HealthCheck/Liveness", options: new()
{
    Predicate = healthCheck => healthCheck.Tags.Any(tag => tag == "liveness"),
    ResultStatusCodes =
    {
        [HealthStatus.Healthy] = StatusCodes.Status200OK,
        [HealthStatus.Degraded] = StatusCodes.Status200OK,
        [HealthStatus.Unhealthy] = StatusCodes.Status503ServiceUnavailable,
    },
});

app.MapHealthChecks("/HealthCheck/Readiness", options: new()
{
    Predicate = healthCheck => healthCheck.Tags.Any(tag => tag == "readiness"),
    ResultStatusCodes =
    {
        [HealthStatus.Healthy] = StatusCodes.Status200OK,
        [HealthStatus.Degraded] = StatusCodes.Status200OK,
        [HealthStatus.Unhealthy] = StatusCodes.Status503ServiceUnavailable,
    },
});

app.MapControllerRoute(
    name: "default",
    pattern: "{controller=Home}/{action=Index}/{id?}")
    .WithStaticAssets();

await app.RunAsync();
