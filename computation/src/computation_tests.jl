# MIT License

# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:

# The above copyright notice and this permission notice shall be included in all
# copies or substantial portions of the Software.

# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.

include("computation.jl")

using Images, ImageView
using Plots
using Makie
using ColorSchemes

using GLMakie
GLMakie.enable_SSAO[] = false



function make_mesh(doses, ct_files, roi_masks, rois_to_plot = [];
    dose_discrepancy = nothing,
    primo_doses = nothing,
    trim_ct_to_body = true,
    trim_doses_to_body = true,
    trim_doses_to_rois = false,
    level_max = 60.0,
    tps_isodose_levels = range(5.0, level_max, length = 5),
    primo_isodose_levels = range(5.0, level_max, length = 5),
    palette_tps = ColorSchemes.isoluminant_cgo_70_c39_n256,
    palette_primo = ColorSchemes.isoluminant_cgo_70_c39_n256,
    tps_isodose_alpha = 0.1f0,
    primo_isodose_alpha = 0.1f0,
    bone_alpha = 0.1f0,
    hot_cold_level = nothing
)
    # Makie.scatter([0.0, 1.0], [0.0, 1.0], [0.0, 1.0])
    scene = Makie.Scene()

    body_mask = haskey(roi_masks, "BODY") ? roi_masks["BODY"] : one.(first(roi_masks)[2])

    function trim_doses(input_doses)
        trimmed_doses = copy(input_doses)
        if trim_doses_to_body
            trimmed_doses[(!).(body_mask)] .= false
        end
        if trim_doses_to_rois
            roi_or = fill(false, size(body_mask)...)
            for (roi_name, roi_color) in rois_to_plot
                roi_or .|= roi_masks[roi_name]
            end
            trimmed_doses[(!).(roi_or)] .= false
        end
        return trimmed_doses
    end
    # show something from CT
    begin
        ct_mesh = make_CT_mesh(ct_files; body_mask = trim_ct_to_body ? body_mask : nothing)
        Makie.mesh!(
            scene,
            ct_mesh,
            color = RGBA{Float32}(1.0f0, 1.0f0, 1.0f0, bone_alpha),
            ssao = false,
            transparency = true,
            shininess = 400.0f0,
            lightposition = Makie.Vec3f0(200, 200, 500),
            # base light of the plot only illuminates red colors
            ambient = Vec3f0(0.3, 0.3, 0.3),
            # light from source (sphere) illuminates yellow colors
            diffuse = Vec3f0(0.4, 0.4, 0.4),
            # reflections illuminate blue colors
            specular = Vec3f0(1.0, 1.0, 1.0),
            show_axis = false,
        )
    end

    return scene
end


"""
    HNSCC_BASE_PATH

Base path to HNSCC data files. They can be downloaded using the provided manifest file.
"""
# const HNSCC_BASE_PATH = "../test-data/HNSCC/HNSCC/"

# ### loading a sample file from the NBIA dataset
# hnscc_7 = load_DICOMs(
#     HNSCC_BASE_PATH * "HNSCC-01-0007/04-29-1997-RT SIMULATION-32176/10.000000-72029/",
#     HNSCC_BASE_PATH * "HNSCC-01-0007/04-29-1997-RT SIMULATION-32176/1.000000-09274/1-1.dcm",
#     HNSCC_BASE_PATH * "HNSCC-01-0007/04-29-1997-RT SIMULATION-32176/1.000000-06686/1-1.dcm",
# )


"""
    test_scene()

Display the `hnscc_7` scene using Makie.jl (for testing purposes).
"""
function test_scene()
    selected_data = hnscc_7
    highlight = [("PTV", RGBA{Float32}(0.0f0, 1.0f0, 0.0f0, 0.1f0))]
    scene = make_mesh(
        selected_data.doses,
        selected_data.ct_files,
        selected_data.roi_masks,
        highlight;
        primo_doses = selected_data.primo_filtered_in_Gy,
        tps_isodose_levels = [],
        primo_isodose_levels = [],
        # palette_primo = ColorSchemes.linear_kry_5_95_c72_n256,
        level_max = 65.0,
        # palette_tps= ColorSchemes.RdBu_11,
        # tps_isodose_alpha=0.5,
        # primo_isodose_alpha=0.2,
        trim_doses_to_rois = true,
        hot_cold_level = 63.0
    )
end
