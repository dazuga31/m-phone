# World systems

`WorldSystems` contains device-adjacent world interactions that reuse the shared renderer or notification bridge.

Current implementation: [ParkingMeter](ParkingMeter/README.md). Its Blueprint/native display owns physical presentation while Lua owns validated parking state and payment orchestration. New general world systems should normally become their own `m-*` resource instead of expanding `m-phone`.
