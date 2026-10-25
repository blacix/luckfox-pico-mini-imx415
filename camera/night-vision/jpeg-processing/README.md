# JPEG processing approach

This approach keeps RKIPC as the camera owner and obtains brightness data by
requesting a JPEG snapshot. It has two components:

- [`image-processor/`](image-processor/README.md) requests a snapshot, decodes
  it with TJpgDec, and prints luma statistics as JSON.
- [`night-vision-service/`](night-vision-service/README.md) runs the image
  processor periodically and switches the shutter and IR LED based on the
  measured mean luma.

The root `./build.sh` stages the two components as separate SDK app packages.
The SDK installs them as `/usr/bin/night-vision-jpeg` and
`/usr/bin/night-vision`. The `S99a-eye-night-vision` init script supervises the
service executable on IMX415 builds.
