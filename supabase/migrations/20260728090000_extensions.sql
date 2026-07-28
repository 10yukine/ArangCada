-- ArangCada — required PostgreSQL extensions.
--
-- PostGIS backs TODA boundary polygons and pickup/dropoff point geometry.
-- Per CLAUDE.md, geofence containment is evaluated server-side in Postgres,
-- never on the client and never through a paid geospatial service.

create extension if not exists postgis;
