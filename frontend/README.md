# Video Dashboard Frontend Container

The frontend container is responsible for hosting the web resources for the Video Dashboard website.

The application was written using C# and runs using ASP.NET Core MVC (.NET 9.0). It is the platform-agnostic web framework within the Microsoft ecosystem.

## Reference: Docker Commands

```sh
# Build
docker build --tag frontend:0.0.0 .

# Run
docker run --detach --publish 8080:8080 --name frontend-container frontend:0.0.0

# Cleanup
docker stop frontend-container && docker rm frontend-container
docker rmi frontend:0.0.0
```
