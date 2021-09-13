module GenieApp

using Images, ImageView, DICOM
using Plots
using Interpolations
using ImageFiltering
using Makie
using LinearAlgebra
using Meshing
using GeometryBasics
using StaticArrays
using GLMakie

GLMakie.enable_SSAO[] = false

using ColorSchemes
using Statistics
using Luxor

function get_transform_matrix(dcm)
    M = zeros(3,3)
    M[2,1] = dcm.ImageOrientationPatient[2] * dcm.PixelSpacing[1]
    M[1,1] = dcm.ImageOrientationPatient[1] * dcm.PixelSpacing[1]
    M[2,2] = dcm.ImageOrientationPatient[5] * dcm.PixelSpacing[2]
    M[1,2] = dcm.ImageOrientationPatient[4] * dcm.PixelSpacing[2]
    M[1,3] = dcm.ImagePositionPatient[1]
    M[2,3] = dcm.ImagePositionPatient[2]
    M[3,3] = 1.0
    return inv(M)
end

function transform_doses(dcm, ct_files)
    dcm_ct = ct_files[1].dcms[1]
    doses = dcm.PixelData * dcm.DoseGridScaling
    percentage_scale = dcm.PixelSpacing ./ dcm_ct.PixelSpacing
    N = length(ct_files[1].dcms)
    new_size = (trunc.(Int, size(doses)[1:2] .* percentage_scale)..., N)
    println("new_size: ", new_size)
    println("percentage_scale: ", percentage_scale)
    println("size(doses): ", size(doses))
    img_rescaled = imresize(doses, new_size)
    out = zeros(size(dcm_ct.PixelData)..., N)
    shift_1 = -trunc(Int, dcm_ct.ImagePositionPatient[2]/dcm_ct.PixelSpacing[2] - dcm.ImagePositionPatient[2] / dcm_ct.PixelSpacing[2])
    shift_2 = -trunc(Int, dcm_ct.ImagePositionPatient[1]/dcm_ct.PixelSpacing[1] - dcm.ImagePositionPatient[1] / dcm_ct.PixelSpacing[1])
    #shift_1 = -trunc(Int, dcm.ImagePositionPatient[2] / dcm.PixelSpacing[2])+90
    #shift_2 = -trunc(Int, dcm.ImagePositionPatient[1] / dcm.PixelSpacing[1])
    for i in 1:N
        copyto!(
            view(out, shift_1:(shift_1+new_size[1]-1), shift_2:(shift_2+new_size[2]-1), N-i+1),
            img_rescaled[:, :, i],
        )
    end
    return out
end

function load_dicom(dir)
    dcms = dcmdir_parse(dir)
    loaded_dcms = Dict()
    # 'dcms' could contain data for different series, so we have to filter by series
    unique_series = unique([dcm.SeriesInstanceUID for dcm in dcms])
    for (idx, series) in enumerate(unique_series)
        dcms_in_series = filter(dcm -> dcm.SeriesInstanceUID == series, dcms)
        pixeldata = extract_pixeldata(dcms_in_series)
        loaded_dcms[idx] = (; pixeldata = pixeldata, dcms = dcms_in_series)
    end
    return loaded_dcms
end

function extract_pixeldata(dcm_array)
    if length(dcm_array) == 1
        return only(dcm_array).PixelData
    else
        return cat([dcm.PixelData for dcm in dcm_array]...; dims = 3)
    end
end

function combine_ct_doses(ct_px, doses, masks, primo_doses)
    # Prepare the data
    out = RGB.(ct_px ./ maximum(ct_px))
    md = maximum(doses)
    for i in eachindex(out)
        out[i] = out[i] + RGB(doses[i] / md, masks[i]/3, primo_doses[i]/md)
    end
    return out
end

function get_ROI_name(dcm, refnumber)
    for ssr in dcm.StructureSetROISequence
        if ssr.ROINumber == refnumber
            return ssr.ROIName
        end
    end
    throw("ROI with number $refnumber not found")
end

function find_matching_seqs(sop_uid, dcm_rs, ROIname)
    seqs = []
    for ssr in dcm_rs.StructureSetROISequence
        if ssr.ROIName != ROIname
            continue
        end
        #println(ssr)
        ROIs = [rcs for rcs in dcm_rs.ROIContourSequence if rcs.ReferencedROINumber == ssr.ROINumber]
        ROI = ROIs[1]
        if ROI.ContourSequence !== nothing
            for seq in ROI.ContourSequence
                alleq = true
                if seq.ContourImageSequence !== nothing
                    for cis in seq.ContourImageSequence
                        #println(cis.ReferencedSOPInstanceUID)
                        if cis.ReferencedSOPInstanceUID != sop_uid
                            alleq = false
                            break
                        end
                    end
                end
                if alleq
                    push!(seqs, seq)
                end
            end
        end
    end

    return seqs
end


function extract_roi_masks(dcm_ct, dcm_rs)
    cont_seq = dcm_rs.ROIContourSequence
    ssroi = dcm_rs.StructureSetROISequence
    w = h = 512
    roi_to_mask = Dict{String,Array{Bool,3}}()

    for cont in cont_seq
        mask = zeros(Bool, 512, 512, length(dcm_ct.dcms))
        name = get_ROI_name(dcm_rs, cont.ReferencedROINumber)
        for (i, cur_dcm) in enumerate(dcm_ct.dcms)
            M = get_transform_matrix(cur_dcm)
            buffer = zeros(UInt32, w, h)
            for cs in find_matching_seqs(cur_dcm.SOPInstanceUID, dcm_rs, name)
                cd = reshape(cs.ContourData, 3, :)
                cd[3,:] .= 1
                cd = M' * cd
                cd = cd[[2,1],:]

                luxvert = map(c -> Luxor.Point(c...), eachcol(cd))
                @imagematrix! buffer begin
                    setantialias(1) # no antialiasing (?)
                    sethue("white")
                    Luxor.poly(luxvert, :fill)
                end 512 512
            end
            graybuff = Gray.(Images.RGB{Float64}.(buffer))
            mask[:, :, i] .= graybuff .> 0.5
        end
        roi_to_mask[string(name)] = mask
    end
    return roi_to_mask
end

function sanitize_fname(fname)
    return replace(fname, r"[%]|[/]" => "_")
end


function make_normals(doses, algo, origin, widths)
    mc = GeometryBasics.Mesh(doses, algo; origin = origin, widths = widths)
    itp = Interpolations.scale(interpolate(doses, BSpline(Quadratic(Periodic(OnGrid())))),
            range(origin[1], origin[1] + widths[1], length=size(doses,1)),
            range(origin[2], origin[2] + widths[2], length=size(doses,2)),
            range(origin[3], origin[3] + widths[3], length=size(doses,3)))
    normals = [normalize(Vec3f0(Interpolations.gradient(itp, Tuple(v)...))) for v in mc.position]

    new_mesh = GeometryBasics.Mesh(GeometryBasics.meta(mc.position; normals=normals), faces(mc))
    return new_mesh
end

function get_slice_thickness(ct_files)
    # we assume that slices have equal distances -- needs to be verified later
    slth = ct_files[1].dcms[1].SliceThickness
    if length(slth) == 0
        locs = map(d -> d.SliceLocation, ct_files[1].dcms)
        locdiffs = diff(locs)
        extr_locdiffs = extrema(locdiffs)
        if extr_locdiffs[1] ≉ extr_locdiffs[2]
            @warn "slices are not equally spaced: $extr_locdiffs"
        end
        slth = abs(mean(locdiffs))
    end
    return slth
end

function ct_origin_widths(ct_files)
    dcm_sample_ct = ct_files[1].dcms[1]
    origin = SA[0.0, 0.0, 0.0]
    widths = SA[
        Float32(dcm_sample_ct.Rows*dcm_sample_ct.PixelSpacing[1]),
        Float32(dcm_sample_ct.Columns*dcm_sample_ct.PixelSpacing[2]),
        Float32(get_slice_thickness(ct_files)*length(ct_files[1].dcms)),
    ]
    return origin, widths
end

function make_CT_mesh(ct_files, isolevel::Float64=1200.0; body_mask=nothing)
    algo_ct = NaiveSurfaceNets(iso=isolevel, insidepositive=true)
    px_data = copy(ct_files[1].pixeldata)
    origin, widths = ct_origin_widths(ct_files)
    if body_mask !== nothing
        min_ct = minimum(px_data)
        px_data[(!).(body_mask)] .= min_ct
    end
    ct_mesh = make_normals(px_data, algo_ct, origin, widths)
    return ct_mesh
end

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
    tps_isodose_alpha=0.1f0,
    primo_isodose_alpha=0.1f0,
    bone_alpha=0.1f0,
    hot_cold_level = nothing,
)
    #Makie.scatter([0.0, 1.0], [0.0, 1.0], [0.0, 1.0])
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
            color=RGBA{Float32}(1.0f0, 1.0f0, 1.0f0, bone_alpha),
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

# modalities:
# RTDOSE: planned dose distribution
# CT: CT scan
# RTSTRUCT: structures in the CT scan

"""
    DoseData
Loaded DICOM files for one RT patient, including CT, planned doses, ROI masks and delivered
doses.
"""
struct DoseData{TCT,TPD,TRM,TDD}
    ct_files::TCT
    doses::TPD
    roi_masks::TRM
    primo_filtered_in_Gy::TDD
end

"""
    load_DICOMs(CT_fname, dose_sum_fname, rs_fname)
Load given DICOM files.
TODO: support multiple dose files.
"""
function load_DICOMs(CT_fname, dose_sum_fname, rs_fname)
    dcm_data = dcm_parse(dose_sum_fname)
    ct_files = load_dicom(CT_fname)
    doses = transform_doses(dcm_data, ct_files)
    
    dcm_rs = dcm_parse(rs_fname)
    roi_masks = extract_roi_masks(ct_files[1], dcm_rs)

    primo_in_Gy = doses .* min.(Ref(1.5), sqrt.(exp.(randn(size(doses)...))))
    slth = get_slice_thickness(ct_files)
    
    filtering_steps = (ct_files[1].dcms[1].PixelSpacing..., slth)
    primo_filtered_in_Gy = imfilter(primo_in_Gy, Kernel.gaussian(0.8 ./ filtering_steps))

    return DoseData(ct_files, doses, roi_masks, primo_filtered_in_Gy)
end

"""
    HNSCC_BASE_PATH
Base path to HNSCC data files. They can be downloaded using the provided manifest file.
"""
const base_to_manifest = "../"

function ct_mesh_from_files(ct_fname)
    ct_files = load_dicom(ct_fname)
    return make_CT_mesh(ct_files)
end

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
        primo_doses=selected_data.primo_filtered_in_Gy,
        tps_isodose_levels = [],
        primo_isodose_levels = [],
        #palette_primo = ColorSchemes.linear_kry_5_95_c72_n256,
        level_max = 65.0,
        #palette_tps= ColorSchemes.RdBu_11,
        #tps_isodose_alpha=0.5,
        #primo_isodose_alpha=0.2,
        trim_doses_to_rois = true,
        hot_cold_level=63.0,
    )
end

## REST API
using Genie, Genie.Router
using Genie.Renderer, Genie.Renderer.Json
using HTTP

Genie.config.run_as_server = true

const DICOM_root = "./static/uploads/"

route("/load", method = GET) do
	message = jsonpayload()
	load_DICOMs(
		    DICOM_root + message["CT_fname"],
		    DICOM_root + message["DoseSum_fname"],
		    DICOM_root + message["RS_fname"]
		)
end

Genie.startup(8001, "127.0.0.1", async = false)

end # module
