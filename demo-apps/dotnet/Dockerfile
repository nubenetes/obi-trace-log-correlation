# Multi-stage build for minimal .NET 8 container image
FROM mcr.microsoft.com/dotnet/sdk:8.0-alpine AS build
WORKDIR /src
COPY DotnetApp.csproj .
RUN dotnet restore
COPY Program.cs .
RUN dotnet publish -c Release -o /app/publish --no-restore

FROM mcr.microsoft.com/dotnet/aspnet:8.0-alpine
WORKDIR /app
COPY --from=build /app/publish .

# Runtime configuration:
# - USE_SYNCHRONOUS_LOGGER=true (default): Uses Serilog synchronous console (OBI Compatible)
# - USE_SYNCHRONOUS_LOGGER=false: Uses default AddConsole() background channel (Demonstrates failure)
ENV USE_SYNCHRONOUS_LOGGER=true
ENV PORT=8086

EXPOSE 8086
USER 10001:10001
ENTRYPOINT ["dotnet", "DotnetApp.dll"]
