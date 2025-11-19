# Video Dashboard Frontend Container

The frontend container is responsible for hosting the web resources for the Video Dashboard website.

The application was written using C# and runs using ASP.NET Core MVC (.NET 9.0). It is the platform-agnostic web framework within the Microsoft ecosystem.

## Reference: Docker Commands

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

## Reference: Useful .NET Resources

- [`dotnet/dotnet-docker`: Distroless .NET Images](https://github.com/dotnet/dotnet-docker/blob/main/documentation/distroless.md)
- [Microsoft Learn: Run an ASP.NET Core app in Docker containers](https://learn.microsoft.com/en-us/aspnet/core/host-and-deploy/docker/building-net-docker-images?view=aspnetcore-9.0)
- [Microsoft Learn: Health checks in ASP.NET Core](https://learn.microsoft.com/en-us/aspnet/core/host-and-deploy/health-checks?view=aspnetcore-9.0)
