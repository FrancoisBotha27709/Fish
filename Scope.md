# Core loop
```mermaid
flowchart LR
	A[Catch Fish] --> B{Should fish\n be processed}
	B -->|Yes| C[Play Minigame]
	B -->|No| E[e]
	C -->|Success| D[Finsih Process]
	D --> E[Sell to vendor]
	E --> |Repeat| B
	F[Fish]
	click F "#fish-roster" "Jump to Fish roster"
	click A "#catching-minigame-archetypes" "Jump to Catching Archetypes"
```

## fish-roster
### basic
- [x] Cod
- [x] Salmon
- [x] Chub
- [x] Perch
### special
- [x] Pufferfish
- [x] Tiger Shark
- [ ] Squid
### idle
- [ ] Crab
- [ ] Lobster
### boss
- [x] Hammerhead

## catching-minigame-archetypes
### bar
