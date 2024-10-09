# l'Arpenteur

_"Est ce que c'est? Un jeu? Un outil? Un jouet? Un simulateur? Un générateur? Un generateur de generateur? Un generateur
de generateur de generateur? Un generateur de generateur de generateur de generateur?"_

_Copilot, 29 dic 2023_

## What is it?

l'Arpenteur is a tool meant to convert a 3D model (in .gltf or .glb format) to a buildable and stable LEGO construction.

For buildable I mean that bricks stack up, layer by layer, floating bricks aren't allowed. The model is also designed to
strive to use larger bricks (thus using the fewest bricks as possible). Stability is guaranteed by, at a given layer, maximizing the number of
connected bricks of the previous layer; thus avoiding "brick piles" that could lead to a fragile construction.


#### Why the name?

"l'Arpenteur", from French, means "the surveyor" in English ("il geometra" in Italian).
And no, I'm not French neither I speak it, but sounded cool so here it is.

# TODO

- [ ] Null value in placement map (current placement map and previous). 
0 null value isn't valid as it is the same for the first placement. UINT16_MAX?
