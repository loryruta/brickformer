#include <cstdlib>
#include <cstdio>

#include "Converter.h"
#include "exporters/GltfExporter.h"

using namespace lego_builder;

int main(int argc, const char** argv)
{
    --argc;
    if (argc < 2)
    {
        fprintf(stderr, "Invalid syntax: %s <input> <slice-side> [output-dir]\n", argv[0]);
        exit(1);
    }
    ++argv;

    const char* input_path = argv[0];
    int slice_side = atoi(argv[1]); // TODO
    const char* output_dir = argc >= 3 ? argv[2] : ".";

    Arpenteur arpenteur(input_path, slice_side);

    OutputToGltf gltf_exporter(arpenteur);
    arpenteur.set_listener(&gltf_exporter);

    arpenteur.run();

    gltf_exporter.complete(output_dir);

    return 0;
}
