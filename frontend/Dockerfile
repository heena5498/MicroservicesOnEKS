# Multi-stage Dockerfile for ASP.NET Core MVC (.NET 9.0) applications


### BUILD STAGE ###

# Use the .NET 9.0 SDK to compile our application into production-ready files
# (e.g., binaries, libraries, dependencies, etc.). This is done in its own stage
# as the SDK image includes software unnecessary during runtime; only the
# production-ready files need to persist in the final image.

FROM mcr.microsoft.com/dotnet/sdk:9.0 AS build

WORKDIR /source

# The .sln and .csproj files contain information about NuGet packages, or
# software dependencies in the Microsoft ecosystem. The "dotnet restore" command
# reads this information and retrieves these software dependencies. Typically,
# when building manually, this step is done implicitly behind build commands;
# however, caching software dependencies in its own layer improves build time,
# minimizes trips to NuGet, and allows reuse across different versions of the
# image. In addition, since this layer is separate from the rest of the build,
# only changes to the software dependencies will cause this layer to be
# re-created.

COPY *.sln .

COPY VideoDashboard.Web/*.csproj ./VideoDashboard.Web/

RUN dotnet restore

# The next half of the build compiles the software dependencies and source code.
# By the end of the build, all production-ready files will be found in the /app
# directory.

COPY VideoDashboard.Web/. ./VideoDashboard.Web/

WORKDIR /source/VideoDashboard.Web

# The "--no-restore" option is used to prevent "dotnet publish" from running
# "dotnet restore" implicitly.
RUN dotnet publish --configuration release --output /app --no-restore


### FINAL STAGE ###

# Use the ASP.NET (.NET 9.0) image as the runtime image. This image only
# contains what is necessary to run the application. The only thing that
# persists from the build stage are the contents of the /app directory.
# Adhering to the principle of least privilege, a non-root user is created and
# used to run the application.

FROM mcr.microsoft.com/dotnet/aspnet:9.0 AS final

# Set useful annotations as defined by the Open Containers Initiative (OCI).
# https://specs.opencontainers.org/image-spec/annotations/
LABEL org.opencontainers.image.title="Video Dashboard Frontend" \
    org.opencontainers.image.description="A web application featuring video upload & streaming as well as analytics tracking capabilities." \
    org.opencontainers.image.version=0.0.0 \
    org.opencontainers.image.source="https://github.com/heena5498/MicroservicesOnEKS" \
    org.opencontainers.image.authors="Marc Gabriel N. Badilla (badillam@umd.edu)"

RUN groupadd --system frontend-group && \
    useradd --no-log-init --system --gid frontend-group frontend-app

USER frontend-app

WORKDIR /app

COPY --chown=frontend-app:frontend-group --from=build /app ./

# The container will listen for HTTP on this port. Note that EXPOSE is used for
# documentation only.
EXPOSE 8080

ENTRYPOINT ["dotnet", "VideoDashboard.Web.dll"]
