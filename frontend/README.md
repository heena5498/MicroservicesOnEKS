# Video Dashboard Frontend Container

The frontend container is responsible for hosting the web resources for the Video Dashboard website.

The application was written using C# and runs using ASP.NET Core MVC (.NET 9.0). It is the platform-agnostic web framework within the Microsoft ecosystem.

## Reference

### Environment Variables

- `VIDEO_DASHBOARD_DEBUG_LIVENESS_PROBE_OVERRIDE_RESULT` (optional): Forces the `/HealthCheck/Liveness` endpoint to return a specific response. Should be one of `HEALTHY`, `DEGRADED`, or `UNHEALTHY`.

- `VIDEO_DASHBOARD_DEBUG_READINESS_PROBE_OVERRIDE_RESULT` (optional): Forces the `/HealthCheck/Readiness` endpoint to return a specific response. Should be one of `HEALTHY`, `DEGRADED`, or `UNHEALTHY`.

### Docker Commands

```sh
# Build
docker build --tag frontend:0.0.0 .

# (Local) Scan
# This requires having a Docker account to use Docker Scout.
docker scout cves local://frontend:0.0.0

# Run
docker run --detach --publish 8080:8080 --name frontend-container frontend:0.0.0

# Cleanup
docker stop frontend-container && docker rm frontend-container
docker rmi frontend:0.0.0
```

### Web Pages

- `/`: This serves as the website's home page. It displays all available videos as a grid of cards. By clicking the "Open Video" button on a card, the user will be routed to `/Home/Video?videoId={videoId}`.

- `/Home/Video?videoId={videoId}`: This serves to provide a detailed look for the video. `videoId` is the video's unique identifier.

- `/Home/Error`: A generic error page for unhandled errors.

- `/HealthCheck/Liveness`: A health check endpoint for determining if the application is running or not.
  - If healthy or degraded, will return a 200 OK response.
  - If unhealthy, will return a 503 Service Unavailable response.

- `/HealthCheck/Readiness`: A health check endpoint for determining if the application is ready to accept requests. This is dependent on the media and analytics services being reachable.
  - If healthy or degraded, will return a 200 OK response.
  - If unhealthy, will return a 503 Service Unavailable response.

### Useful .NET Resources

- [`dotnet/dotnet-docker`: Distroless .NET Images](https://github.com/dotnet/dotnet-docker/blob/main/documentation/distroless.md)
- [Microsoft Learn: Run an ASP.NET Core app in Docker containers](https://learn.microsoft.com/en-us/aspnet/core/host-and-deploy/docker/building-net-docker-images?view=aspnetcore-9.0)
- [Microsoft Learn: Health checks in ASP.NET Core](https://learn.microsoft.com/en-us/aspnet/core/host-and-deploy/health-checks?view=aspnetcore-9.0)
