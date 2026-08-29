# Desktop UI bridge compatibility

This folder contains only the transitional UI router that connects the shared compiled browser callback registry to spatial WebUI instances created by `m-desktop`.

World interactions, monitor props, camera focus, virtual pointer input, materials and spatial lifecycle belong to `m-desktop`. The bridge retains existing `m-phone` client exports while Desktop Apps are migrated behind stable resource APIs.

Do not add camera, material, world-coordinate or gameplay-domain logic here.
