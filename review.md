# Outstanding Review Items

## Camera selection and `rkipc` startup

### Verify camera-specific startup and overlay selection

The IMX415 service stops an existing `rkipc` before starting its supervisor.
The SDK launcher can also start `rkipc` after its stock setup. Confirm on an
IMX415 boot whether the SDK launcher starts a process before the project
service takes ownership, or whether the project service is the only launcher.

Build each camera selection in sequence and inspect the SDK overlay after each
run. Confirm that switching from IMX415 to SC3336 removes the project camera
service, supervisor, INI, and IQ file, while retaining the LED service. On the
device, confirm that SC3336 uses the SDK startup/configuration and IMX415 uses
the project startup/configuration.

### Observe log growth during a long-running camera session

The supervisor keeps only the most recent `rkipc` attempt in
`/tmp/rkipc.log`, clearing the file before each retry. A single long-running
attempt can still grow the log. Observe actual growth before deciding whether
additional limits are needed.
