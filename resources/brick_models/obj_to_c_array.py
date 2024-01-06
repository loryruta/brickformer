import sys


v = []
vn = []
vt = []

out_vertices = []

if len(sys.argv) != 2:
    print(f"Invalid syntax: {sys.argv[0]} <obj-file>")
    exit(1)

f = open(sys.argv[1], "rt")

for line in f.readlines():
    cmd = line.split(" ")[0]
    if cmd == 'v':
        v.append([float(x) for x in line.split(" ")[1:4]])
    elif cmd == 'vn':
        vn.append([float(x) for x in line.split(" ")[1:4]])
    elif cmd == 'vt':
        vt.append([float(x) for x in line.split(" ")[1:3]])
    elif cmd == 'f':
        if len(line.split(" ")) != 4:
            print("WARNING: Face isn't triangular")
            continue

        for raw_v in line.split(" ")[1:4]:
            # f v/vt/vn ...
            vi  = int(raw_v.split("/")[0]) - 1
            vti = int(raw_v.split("/")[1]) - 1
            vni = int(raw_v.split("/")[2]) - 1
            out_vertices.append({
                "position": v[vi],
                "texcoord": vt[vti],
                "normal":   vn[vni]
            })

for out_v in out_vertices:
    print("{.m_position{%.3ff, %.3ff, %.3ff}, .m_normal{%.3ff, %.3ff, %.3ff}, .m_texcoord{%.3ff, %.3ff}}," % (
        out_v["position"][0], out_v["position"][1], out_v["position"][2],
        out_v["normal"][0], out_v["normal"][1], out_v["normal"][2],
        out_v["texcoord"][0], out_v["texcoord"][1],
        ))
