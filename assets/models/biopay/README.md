Drop the production BioPay face embedding model in this directory as:

- `mobilefacenet_int8.tflite`
- `mobilefacenet_int8.contract.json`

The current scanner pipeline is wired to load that asset path at runtime.
Until the file is present, BioPay camera guidance and face detection can run,
but embedding generation and server enrollment/matching will remain unavailable.

After placing the `.tflite` file, generate the contract with:

- `dart tool/biopay_model_contract.dart --generate`

Release readiness validates the contract when a BioPay model is bundled for a
release. If either the model or contract file is present, the check must pass
and the checksum, byte size, and tensor metadata must match the bundled file.
