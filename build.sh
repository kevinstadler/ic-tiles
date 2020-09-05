#!/bin/sh

# source = ne_
# manually use QGIS to make qgis.shp
# for a0: merge geometry into a0.shp
# for a0: join qgis.shp and a0.shp into a0-joined.shp
# for a1: ogr2ogr qgis.shp to a1-joined.shp
# convert to geojson
# build vector tiles (goes to zoom 10 for a0, 5 for a1)

DATASET=$1
if [ -z "$DATASET" ]; then
  DATASET="a0"
fi

if [ ! -d "data/$DATASET" ]; then
  mkdir -p "data/$DATASET"
fi
cd "data/$DATASET"

if [ "$DATASET" = "a0" ]; then
  COLORDATA="ne_10m_admin_0_countries" # 173-4 entities
  #COLORDATA="ne_110m_admin_0_sovereignty" # 157-8 entities
  #COLORDATA="ne_110m_admin_0_map_units"
elif [ "$DATASET" = "a1" ]; then
  COLORDATA="ne_10m_admin_1_states_provinces"
fi

if [ ! -f "$COLORDATA.shp" ]; then
  if [ ! -f "$COLORDATA.zip" ]; then
    wget https://www.naturalearthdata.com/http//www.naturalearthdata.com/download/110m/cultural/$COLORDATA.zip || exit 1
  fi
  unzip "$COLORDATA.zip" || exit 1
fi

if [ ! -f "qgis.shp" ]; then
  echo "Fire up QGIS to run topological coloring and create qgis.shp from $COLORDATA.shp (adding columns col0, col1, col2)..."
  exit 1
fi
# _col0 = balanced number of features per colour
# _col1 = balanced assigned area per colour
# _col2 = balanced distance between colours
# a0_col0 = 5
# a0_col1 = 5
# a0_col2 = 5
# a1_col0 = 7
# a1_col1 = 6
# a1_col2 = 6

if [ "$DATASET" = "a0" ]; then
  #ogrinfo -dialect SQLite -sql "UPDATE $COLORDATA SET ISO_A2 = 'FR' WHERE ADM0_A3 = 'FRA';" "$COLORDATA.shp"
  if [ ! -f "iso.csv" ]; then
    ogr2ogr -f CSV iso.csv "$COLORDATA.shp" -dialect sqlite -sql "SELECT ADM0_A3, NAME_EN, FORMAL_EN FROM $COLORDATA"  || exit 1 # WHERE ISO_A2 != 'UM'"
  fi

  i=1
  #for ADMA3 in `tail -n +2 iso.csv`; do
  tail -n +2 iso.csv | while IFS=, read -r ADMA3 NAME LONGNAME; do
    if [ ! -f "$ADMA3.geojson" ]; then
      echo "Downloading border #$i ($ADMA3, query: $LONGNAME)"
      wget --no-verbose --show-progress --progress=dot:binary -O "$ADMA3.geojson" "https://nominatim.openstreetmap.org/search?q=$NAME&format=geocodejson&polygon_geojson=1&limit=1" || exit 1
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
    echo "Merging individual boundaries into one shapefile..." # -field_strategy FirstLayer -src_geom_type POLYGON 
    ogrmerge.py -single -src_layer_field_name adm0_a3 -src_layer_field_content "{AUTO_NAME}" -o "$DATASET.shp" "*.geojson" || exit 1
  fi

  if [ ! -f "$DATASET-joined.shp" ]; then

    FIELDS="col0,col1,col2,pop_est"

    # based on https://gis.stackexchange.com/questions/95746/join-a-csv-file-to-shapefile-using-gdal-ogr/95757
    # TODO figure out how to do in-file update
    ogr2ogr -sql "SELECT $FIELDS FROM $DATASET JOIN 'qgis.shp'.qgis ON $DATASET.adm0_a3 = qgis.adm0_a3" "$DATASET-joined.shp" "$DATASET.shp" || exit 1

    # the old way (multiple calls because add/drop column not possible in SQLite)
  #  ogrinfo -sql "ALTER TABLE $DATASET DROP COLUMN geocoding" "$DATASET.shp"
  #  ogrinfo -sql "ALTER TABLE $DATASET ADD COLUMN color7 INTEGER" "$DATASET.shp"
  #  ogrinfo -dialect SQLite -sql "UPDATE $DATASET SET color7 = (SELECT MAPCOLOR7 FROM '$COLORDATA.shp'.$COLORDATA WHERE iso_a2 = $DATASET.ISO_A2)" "$DATASET.shp"
  fi


elif [ "$DATASET" = "a1" ]; then
  ogr2ogr -f CSV iso.csv "$COLORDATA.shp" -dialect sqlite -sql "SELECT adm1_code, admin, iso_a2, name, type, name_en, type_en, COALESCE(gn_name, name) AS searchname FROM $COLORDATA WHERE name IS NOT NULL"  || exit 1

  # i=1
  # #for ADMA3 in `tail -n +2 iso.csv`; do
  # tail -n +2 iso.csv | while IFS=, read -r ADMCODE ADMINCOUNTRY ISO NAME TYPE NAMEEN TYPEEN SEARCHNAME; do
  #   if [ ! -f "$ADMCODE.geojson" ]; then
  #     echo "\n\nDownloading border #$i (query: $NAME, $ADMINCOUNTRY) to $ADMCODE.geojson"
  #     wget --no-verbose --show-progress --progress=dot:binary -O "$ADMCODE.geojson" "https://nominatim.openstreetmap.org/search?county=$NAME&country=$ADMINCOUNTRY&format=geocodejson&polygon_geojson=1&limit=1"

  #     if [ `stat -f '%z' "$ADMCODE.geojson"` -lt 550 ]; then
  #       echo "\n\nDownloading border #$i (query: $NAME, $ADMINCOUNTRY) to $ADMCODE.geojson"
  #       rm "$ADMCODE.geojson"
  #       # TODO use polygon_threshold=0.0 to reduce filesize...
  #       wget --no-verbose --show-progress --progress=dot:binary -O "$ADMCODE.geojson" "https://nominatim.openstreetmap.org/search?county=$NAME&country=$ADMINCOUNTRY&format=geocodejson&polygon_geojson=1&limit=1"
  #     fi
  #     if [ `stat -f '%z' "$ADMCODE.geojson"` -lt 550 ]; then
  #       echo "$ADMCODE.geojson seems a bit small, trying again as a state..."
  #       wget --no-verbose --show-progress --progress=dot:binary -O "$ADMCODE.geojson" "https://nominatim.openstreetmap.org/search?state=$NAME&country=$ADMINCOUNTRY&format=geocodejson&polygon_geojson=1&limit=1"
  #       # wget -O - "https:// ..." | gzip > "$ISOA2.geojson.gz"
  #   # TODO then use /vsigzip/filename to open...
  #     fi
  #     if [ `stat -f '%z' "$ADMCODE.geojson"` -lt 550 ]; then
  #       echo "$ADMCODE.geojson still a bit small, just try stupid unstructured query..."
  #       rm "$ADMCODE.geojson"
  #       wget --no-verbose --show-progress --progress=dot:binary -O "$ADMCODE.geojson" "https://nominatim.openstreetmap.org/search?q=$NAME&format=geocodejson&polygon_geojson=1&limit=1"
  #     fi
  #   fi
  #   i=$((i+1))
  # done

  FIELDS="col0,col1,col2,name,gn_name,admin,labelrank"

  # don't merge a1 because nominatim results too unreliable (and high-res), just simplify natural earth...
  ogr2ogr -select "$FIELDS" "$DATASET-joined.shp" "qgis.shp" || exit 1
fi

cd ../..
if [ ! -f "$DATASET.geojson.gz" ]; then
  echo "Creating $DATASET.geojson.gz for tile creation"
  ogr2ogr -f GeoJSON /vsistdout/ "data/$DATASET/$DATASET-joined.shp" | gzip > "$DATASET.geojson.gz" || exit 1
fi

if [ ! -d "$DATASET" ]; then
  echo "Building tiles..."
  # maximum-zoom=g makes things very blurry, so hardcode instead
  tippecanoe --maximum-zoom=g --extend-zooms-if-still-dropping --simplify-only-low-zooms --no-tile-compression --output-to-directory="$DATASET" "$DATASET.geojson.gz" || exit 1
fi
