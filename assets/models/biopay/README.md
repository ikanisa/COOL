Drop the production BioPay face embedding model in this directory as:

- `mobilefacenet_int8.tflite`

The current scanner pipeline is wired to load that asset path at runtime.
Until the file is present, BioPay camera guidance and face detection can run,
but embedding generation and server enrollment/matching will remain unavailable.
