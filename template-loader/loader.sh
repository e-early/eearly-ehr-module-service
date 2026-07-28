#!/bin/sh
set -e

EHRBASE_URL="${EHRBASE_URL:?EHRBASE_URL is not set}"

echo "Checking EHRbase availability..."

if ! curl -sf "$EHRBASE_URL/ehrbase/rest/status" > /dev/null; then
  echo "EHRbase is not available. Exiting."
  exit 1
fi

echo "EHRbase is available. Loading templates..."

api_template_url="$EHRBASE_URL/ehrbase/rest/openehr/v1/definition/template/adl1.4"

for f in /templates/*.opt; do
  [ -e "$f" ] || continue
  echo "Uploading $f"
  http_code=$(curl -s -o /dev/null -w "%{http_code}" -X POST "$api_template_url" \
    -H "Content-Type: application/xml" \
    --data-binary "@$f")
  case "$http_code" in
    200|201) echo "Successfully uploaded template $f" ;;
    409) echo "Template already loaded: $f" ;;
    *) echo "Error uploading $f (status: $http_code)"; exit 1 ;;
  esac
done

echo "All templates loaded."
