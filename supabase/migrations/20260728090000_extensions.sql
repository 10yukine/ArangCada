-- ArangCada — required PostgreSQL extensions.
--
-- PostGIS backs TODA boundary polygons and pickup/dropoff point geometry.
-- never on the client and never through a paid geospatial service.

create extension if not exists postgis;
