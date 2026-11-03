# syntax=docker/dockerfile:1
# Stock nginx on the stable branch; the minor version tracks patch releases on rebuild.
FROM nginx:1.30-alpine

# VarPad (https://github.com/gritee/VarPad): a single self-contained index.html.
# Pinned to a commit because the image tag is the last commit that changed web/: to update,
# bump VARPAD_COMMIT and the checksum (shasum -a 256 index.html at that commit).
ARG VARPAD_COMMIT=4c8721fb4599d72848f8341e9c16ea145a841795
ADD --checksum=sha256:eebcb4816bc5557e18f45eb3c452542a365d3ccb240ff3eb76abbf3d5caa6013 \
    --chmod=644 \
    https://raw.githubusercontent.com/gritee/VarPad/${VARPAD_COMMIT}/index.html \
    /usr/share/nginx/html/index.html
