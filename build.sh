#!/bin/sh
DATASET=$1
if [ -z "$DATASET" ]; then
  DATASET="a0"
fi

if [ ! -d "data/$DATASET" ]; then
  mkdir -p "data/$DATASET"
fi
cd "data/$DATASET"

COLORDATA="ne_10m_admin_0_countries" # 173-4
#COLORDATA="ne_110m_admin_0_sovereignty" # 157-8
#COLORDATA="ne_110m_admin_0_map_units"
if [ ! -f "$COLORDATA.shp" ]; then
  if [ ! -f "$COLORDATA.zip" ]; then
    wget https://www.naturalearthdata.com/http//www.naturalearthdata.com/download/110m/cultural/$COLORDATA.zip
  fi
  unzip "$COLORDATA.zip"
  ogrinfo -dialect SQLite -sql "UPDATE $COLORDATA SET ISO_A2 = 'FR' WHERE ADM0_A3 = 'FRA';" "$COLORDATA.shp"
fi

if [ ! -f "iso.csv" ]; then
  ogr2ogr -f CSV iso.csv "$COLORDATA.shp" -dialect sqlite -sql "SELECT ADM0_A3, NAME_EN, FORMAL_EN FROM $COLORDATA" # WHERE ISO_A2 != 'UM'"
fi

i=1
#for ADMA3 in `tail -n +2 iso.csv`; do
tail -n +2 iso.csv | while IFS=, read -r ADMA3 NAME LONGNAME; do
  if [ ! -f "$ADMA3.geojson" ]; then
    echo "Downloading border #$i ($ADMA3, query: $LONGNAME)"
    wget -O "$ADMA3.geojson" "https://nominatim.openstreetmap.org/search?q=$NAME&format=geocodejson&polygon_geojson=1&limit=1"
    # wget -O - "https:// ..." | gzip > "$ISOA2.geojson.gz"
#    wget -O "$ISOA2.geojson" "https://nominatim.openstreetmap.org/search?country=$ISOA2&format=geocodejson&polygon_geojson=1&limit=1"
# TODO then use /vsigzip/filename to open...
  fi
  i=$((i+1))
done

if [ -f "$DATASET.shp" ]; then
  echo "$DATASET.shp exists, skipping merging of community polygons."
else
  # merge and strip
  echo "Merging individual boundaries into one shapefile..."
  ogrmerge.py -single -field_strategy FirstLayer -src_layer_field_name adm0_a3 -src_layer_field_content "{AUTO_NAME}" -o "$DATASET.shp" "*.geojson"
fi

if [ ! -f "$DATASET-merged.shp" ]; then
  # based on https://gis.stackexchange.com/questions/95746/join-a-csv-file-to-shapefile-using-gdal-ogr/95757
  # TODO figure out how to do in-file update
  ogr2ogr -sql "SELECT adm0_a3, mapcolor7, mapcolor8, mapcolor9 FROM $DATASET JOIN '$COLORDATA.shp'.$COLORDATA ON $DATASET.adm0_a3 = $COLORDATA.ADM0_A3" "$DATASET-merged.shp" "$DATASET.shp"

  # the old way (multiple calls because add/drop column not possible in SQLite)
#  ogrinfo -sql "ALTER TABLE $DATASET DROP COLUMN geocoding" "$DATASET.shp"
#  ogrinfo -sql "ALTER TABLE $DATASET ADD COLUMN color7 INTEGER" "$DATASET.shp"
#  ogrinfo -dialect SQLite -sql "UPDATE $DATASET SET color7 = (SELECT MAPCOLOR7 FROM '$COLORDATA.shp'.$COLORDATA WHERE iso_a2 = $DATASET.ISO_A2)" "$DATASET.shp"
fi

cd ../..
if [ ! -f "$DATASET.geojson.gz" ]; then
  echo "Creating $DATASET.geojson.gz for tile creation"
  ogr2ogr -f GeoJSON /vsistdout/ "data/$DATASET/$DATASET-merged.shp" | gzip > "$DATASET.geojson.gz"
fi

if [ ! -d "$DATASET" ]; then
  echo "Building tiles..."
  # maximum-zoom=g makes things very blurry, so hardcode instead
  tippecanoe --maximum-zoom=g --extend-zooms-if-still-dropping --simplify-only-low-zooms --no-tile-compression --output-to-directory="$DATASET" "$DATASET.geojson.gz"
fi
