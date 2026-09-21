extends Node
## Autoload. Global signal bus so unrelated nodes (camera, environment, UI...)
## can react to vision-darkening without holding references to each other.

signal darken_vision_changed(intensity: float)