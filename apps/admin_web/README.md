# ArangCada Admin

Standalone Flutter Web console for LGU/TODA internal MVP evaluation. All records and mutations are synthetic and in-memory; refreshing resets the console. This target does not import or depend on `apps/mobile`.

## Run locally

```powershell
E:\Dev\flutter\bin\flutter.bat run -d chrome
```

Without configuration, the MapLibre canvas uses OpenStreetMap raster tiles. To use the approved MapTiler provider during development, inject a restricted public key at build or run time; never commit it:

```powershell
E:\Dev\flutter\bin\flutter.bat run -d chrome --dart-define=MAPTILER_KEY=YOUR_RESTRICTED_KEY
```

## Verify

```powershell
E:\Dev\flutter\bin\flutter.bat analyze
E:\Dev\flutter\bin\flutter.bat test
E:\Dev\flutter\bin\flutter.bat build web --release
```
