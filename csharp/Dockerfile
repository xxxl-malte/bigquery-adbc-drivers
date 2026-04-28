FROM mcr.microsoft.com/dotnet/sdk:8.0 AS base

WORKDIR /repo/csharp

# Copy the csharp directory contents (context = csharp/)
COPY . .

# Note: the host has a symlink test/Apache.Arrow.Adbc.Tests -> ../arrow-adbc/...
# which is excluded in .dockerignore. The ProjectReference paths in the csproj
# files already point directly into arrow-adbc/, so the symlink is not needed.

# Restore NuGet packages for both projects
RUN dotnet restore src/AdbcDrivers.BigQuery.csproj && \
    dotnet restore test/AdbcDrivers.BigQuery.Tests.csproj

# -------------------------------------------------------------------
# Stage: build
# -------------------------------------------------------------------
FROM base AS build

RUN dotnet build src/AdbcDrivers.BigQuery.csproj -c Release --no-restore

# -------------------------------------------------------------------
# Stage: test
# -------------------------------------------------------------------
FROM base AS test

RUN dotnet build test/AdbcDrivers.BigQuery.Tests.csproj -c Debug --no-restore

# Default: run unit tests (no BigQuery credentials required)
ENTRYPOINT ["dotnet", "test", "test/AdbcDrivers.BigQuery.Tests.csproj", \
            "--no-build", "-c", "Debug", "--logger", "console;verbosity=detailed"]
