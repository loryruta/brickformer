# BFC Format

BFC stands for BrickFormer Converter format and is an extension of the glb format.

The model vertices contain `POSITION`, `NORMAL`, `COLOR` and `_OUTLINE_GUIDE` (custom attribute).

The outline guide is used for rendering, and if two primitives with different outline guides are rendered close to each
other then an **outline** is drawn in between.

The `extras` field contains a JSON -formatted string having this format;

```json
{
  "name": "CesiusMan",
  "description": "BrickFormer Converter",
  "version": "v1.1.1a",
  "version_full": "v1.1.1a",
  "commit_hash": "73cebf8ece5e8f3edd6e5c148d19c6585f33516a",
  "commit_timestamp": "1761950911",
  "created_at": "2025-11-21 21:52:49",
  "subslice_ranges": <see-below>,
  "placements": <see-below>,
  "brick_quantities": <see-below>
}
```

`subslice_ranges` is an array of `[start_vertex, end_vertex]` which tells the first vertex (included) and last vertex (
excluded) of each subslice.

`placements` is a `uint32` binary buffer with the following format:
```
                Uint 0 |        Uint 1 |        Uint 2 |   
<num placements slice 0><bid><x><z><cid><bid><x><z><cid> ... 
<num placements slice 1><bid><x><z><cid> ...
```

- `(x, z)` identify the X/Z axes position of the brick.
  Y is the height and increases every slice.

`brick_quantities` is an array of JSON objects, e.g.:
```json
[{
  "bid": 5,
  "cid": 1,
  "quantity": 100
},
  ...]
```

**NOTE**:

- `bid`: BID is an internal identifier for the brick.
  It is rotation-dependent meaning the same brick with different rotations is internally recognized as two
  different bricks with independent BIDs.
- `cid`: CID is an internal identifier for the brick color.
