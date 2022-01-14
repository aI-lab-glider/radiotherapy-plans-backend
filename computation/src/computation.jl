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

using DICOM
using Interpolations
using ImageFiltering

using LinearAlgebra
using Meshing
using MeshIO
using GeometryBasics
using StaticArrays
using Statistics
using Luxor
using ColorTypes
using ImageDistances
using FileIO


function get_transform_matrix(dcm)
    M = zeros(3, 3)
    M[2, 1] = dcm.ImageOrientationPatient[2] * dcm.PixelSpacing[1]
    M[1, 1] = dcm.ImageOrientationPatient[1] * dcm.PixelSpacing[1]
    M[2, 2] = dcm.ImageOrientationPatient[5] * dcm.PixelSpacing[2]
    M[1, 2] = dcm.ImageOrientationPatient[4] * dcm.PixelSpacing[2]
    M[1, 3] = dcm.ImagePositionPatient[1]
    M[2, 3] = dcm.ImagePositionPatient[2]
    M[3, 3] = 1.0
    return inv(M)
end


"""
    get_transform_matrix_ct(dcm)

Get pixel to mm transformation matrix for CT image `dcm`.
Based on https://dicom.innolitics.com/ciods/ct-image/image-plane/00200037
"""
function get_transform_matrix_ct(dcm)
    Xxyz = dcm.ImageOrientationPatient[1:3]
    Yxyz = dcm.ImageOrientationPatient[4:6]
    Δi, Δj = dcm.PixelSpacing
    S = dcm.ImagePositionPatient
    M = SMatrix{4,4,Float64}([
        Xxyz[1]*Δi Yxyz[1]*Δj 0 S[1]
        Xxyz[2]*Δi Yxyz[2]*Δj 0 S[2]
        Xxyz[3]*Δi Yxyz[3]*Δj 0 S[3]
        0 0 0 1
    ])

    return M
end

"""
    get_dose_grid(dcm)


https://dicom.innolitics.com/ciods/rt-dose/rt-dose/3004000c
"""
function get_dose_grid(dcm)
    Xxyz = dcm.ImageOrientationPatient[1:3]
    Yxyz = dcm.ImageOrientationPatient[4:6]
    Nx, Ny, Nz = size(dcm.PixelData)
    Δi, Δj = dcm.PixelSpacing
    S = dcm.ImagePositionPatient

    #TODO: do we even need to handle other cases?
    @assert Yxyz[1] == 0.0
    @assert Yxyz[3] == 0.0
    @assert Xxyz[2] == 0.0
    @assert Xxyz[3] == 0.0
    @assert dcm.GridFrameOffsetVector[1] == 0.0

    # TODO: check orientation of S
    udg = unique(diff(dcm.GridFrameOffsetVector))
    if !isa(dcm.SliceThickness, Real)
        println("Substituting SliceThickness: ", dcm.SliceThickness)
        dcm.SliceThickness = mean(udg) # saving for later
    end
    # note that X and Y axes are swapped for the handled case
    if length(udg) == 1
        # grid is uniform, can use ranges
        return (
            range(S[2]; length = Nx, step = Xxyz[1] * Δi),
            range(S[1]; length = Ny, step = Yxyz[2] * Δj),
            range(S[3]; length = Nz, step = udg[]),
        )
    else
        println("Uneqal frame offsets!")
        println("udg = ", udg)
        return (
            range(S[2]; length = Nx, step = Xxyz[1] * Δi),
            range(S[1]; length = Ny, step = Yxyz[2] * Δj),
            S[3] .+ dcm.GridFrameOffsetVector,
        )
    end
end

function fill_doses_slice(out, dose_itp, M, z)
    # note that X and Y axes are swapped for the handled case
    for x in axes(out, 1), y in axes(out, 2)
        pos = M * @SVector [(y - 1), (x - 1), 0, 1]
        out[x, y, z] = dose_itp(pos[2], pos[1], pos[3])
    end
end

function transform_doses(dcm, ct_files)
    dcm_ct = ct_files[1].dcms[1]
    doses = dcm.PixelData * dcm.DoseGridScaling
    N = length(ct_files[1].dcms)

    # 1) go from CT position to global coordinates
    # 2) go from global coordinates to dose position 
    dose_grid = get_dose_grid(dcm)
    dose_itp = extrapolate(interpolate(dose_grid, doses, Gridded(Linear())), zero(eltype(doses)))

    out = zeros(size(dcm_ct.PixelData)..., N)
    for z in 1:N
        M = get_transform_matrix_ct(ct_files[1].dcms[z])
        fill_doses_slice(out, dose_itp, M, z)
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
        out[i] = out[i] + RGB(doses[i] / md, masks[i] / 3, primo_doses[i] / md)
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
                else
                    alleq = false
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
        mask = zeros(Bool, w, h, length(dcm_ct.dcms))
        name = get_ROI_name(dcm_rs, cont.ReferencedROINumber)
        for (i, cur_dcm) in enumerate(dcm_ct.dcms)
            ct_transl = [cur_dcm.ImagePositionPatient[1:2]..., 0.0]
            M = get_transform_matrix(cur_dcm)
            buffer = zeros(UInt32, w, h)
            for cs in find_matching_seqs(cur_dcm.SOPInstanceUID, dcm_rs, name)

                cd = reshape(cs.ContourData, 3, :)
                cd[3, :] .= 1
                cd .-= ct_transl
                cd = M' * cd
                cd = cd[[2, 1], :] .- [w / 2, h / 2]

                luxvert = map(c -> Luxor.Point(c...), eachcol(cd))
                @imagematrix! buffer begin
                    setantialias(1) # no antialiasing (?)
                    sethue("white")
                    Luxor.poly(luxvert, :fill)
                end 512 512
            end
            graybuff = Gray.(ColorTypes.RGB{Float64}.(buffer))
            mask[:, :, i] .= graybuff .> 0.5
        end
        roi_to_mask[string(name)] = mask
    end
    return roi_to_mask
end

function make_normals(doses, algo, origin, widths)
    mc = GeometryBasics.Mesh(doses, algo; origin = origin, widths = widths)
    itp = Interpolations.scale(interpolate(doses, BSpline(Quadratic(Periodic(OnGrid())))),
        range(origin[1], origin[1] + widths[1], length = size(doses, 1)),
        range(origin[2], origin[2] + widths[2], length = size(doses, 2)),
        range(origin[3], origin[3] + widths[3], length = size(doses, 3)))
    normals = [normalize(Vec3f0(Interpolations.gradient(itp, Tuple(v)...))) for v in mc.position]

    new_mesh = GeometryBasics.Mesh(GeometryBasics.meta(mc.position; normals = normals), faces(mc))
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
        Float32(dcm_sample_ct.Rows * dcm_sample_ct.PixelSpacing[1]),
        Float32(dcm_sample_ct.Columns * dcm_sample_ct.PixelSpacing[2]),
        Float32(get_slice_thickness(ct_files) * length(ct_files[1].dcms)),
    ]
    return origin, widths
end

"""
    make_CT_mesh(ct_files, isolevel::Float64=1200.0; body_mask=nothing)

Make a mesh representing the given isolevel of a CT image given in `ct_files`. The argument
`ct_files` can be taken from `DoseData`.

# Arguments

* `isolevel` should be specified in [Hounsfield scale](https://en.wikipedia.org/wiki/Hounsfield_scale).
* `body_mask` can be `nothing` (and then it does nothing) or a 3D boolean array of the same
    size as CT pixel array. If specified, the CT images is trimmed to `true` values in the
    given array.
"""
function make_CT_mesh(ct_files; isolevel::Float64 = 1200.0, body_mask = nothing)
    algo_ct = NaiveSurfaceNets(iso = isolevel, insidepositive = true)
    px_data = copy(ct_files[1].pixeldata)
    origin, widths = ct_origin_widths(ct_files)
    if body_mask !== nothing
        min_ct = minimum(px_data)
        px_data[(!).(body_mask)] .= min_ct
    end
    ct_mesh = make_normals(px_data, algo_ct, origin, widths)
    return ct_mesh
end

"""
    read_f0(fname)

Read Primo f0 file with simulated delivered doses.
"""
function read_f0(fname)
    file = open(fname)
    for i in 1:7 # skipping comments
        readline(file)
    end
    # x y z sizes (x-z change within a single slice)
    # changes to z, x, y for returning
    img_size = parse.(Int, split(readline(file))[2:end])
    readline(file) # comment
    voxel_size = parse.(Float64, split(readline(file))[2:end]) # in cm
    #println("PRIMO voxel size:", voxel_size)
    #println("PRIMO img size:", img_size)
    new_size = (img_size[3], img_size[1], img_size[2])
    doses = zeros(new_size...) # doses in eV/g
    two_sigmas = zeros(new_size...) # errors of doses
    readline(file)
    for z in 1:img_size[3]
        readline(file)
        readline(file)
        for y in 1:img_size[2]
            readline(file)
            readline(file)
            for x in 1:img_size[1]
                rl = readline(file)
                curline = parse.(Float64, split(rl))
                doses[z, x, y] = curline[1]
                two_sigmas[z, x, y] = curline[2]
            end
        end
    end

    if all(z_pos_diffs(ct_files) .> 0)
        doses .= reverse(doses; dims = 3)
        two_sigmas .= reverse(two_sigmas; dims = 3)
    end

    close(file)
    dcm_ct = ct_files[1].dcms[1]
    even_newer_size = (Int(dcm_ct.Rows), Int(dcm_ct.Columns), new_size[3])
    doses_rescaled = imresize(doses, even_newer_size)
    two_sigmas_rescaled = imresize(two_sigmas, even_newer_size)
    return doses_rescaled, two_sigmas_rescaled
end


function my_deduplicate_knots!(knots)
    last_knot = first(knots)
    for i = eachindex(knots)
        if i == 1
            continue
        end
        if knots[i] == last_knot || knots[i] <= knots[i-1]
            @inbounds knots[i] = nextfloat(knots[i-1])
        else
            last_knot = @inbounds knots[i]
        end
    end
    knots
end

function calc_dvh_for_doses(q, doses)
    if length(doses) == 0
        return NaN .* q
    end
    doses = vec(doses)
    sdoses = sort(doses)

    target_range = range(0.0, 1.0; length = length(doses))
    sdoses = my_deduplicate_knots!(sdoses)
    f = extrapolate(interpolate((sdoses,), target_range, Gridded(Linear())), Flat())
    return 1.0 .- f.(q)
end

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

function confusion_matrix_at_level(doses_expected, doses_measured, mask_inds, level::Real)
    mask_expected = doses_expected .>= level
    mask_measured = doses_measured .>= level
    tn = 0
    tp = 0
    fn = 0
    fp = 0
    for i in mask_inds
        if mask_expected[i] && mask_measured[i]
            tp += 1
        elseif mask_expected[i] && !(mask_measured[i])
            fn += 1
        elseif !(mask_expected[i]) && mask_measured[i]
            fp += 1
        else
            tn += 1
        end
    end
    return (; tp = tp, tn = tn, fn = fn, fp = fp)
end

function hausdorff_distance(doses_expected, doses_measured, mask, weights, level::Real)
    d = GenericHausdorff(ImageDistances.MaxReduction(), ImageDistances.MaxReduction(), weights)
    mask_expected = (doses_expected .>= level) .& mask
    mask_measured = (doses_measured .>= level) .& mask
    return d(mask_expected, mask_measured)
end



"""
    calc_plots_data(dd::DoseData; N=1000)

Calculate FPRs, FNRs, Dice coefficients and Hausdorff distances for each ROI
for each isodose level from 0 to maximum of planned doses, at `N` levels.
"""
function calc_plots_data(dd::DoseData; N = 1000)

    roi_to_plotdata = Dict{String,NamedTuple}()
    md = max(maximum(dd.doses), maximum(dd.primo_filtered_in_Gy))
    q = range(0.0, md; length = N)

    ct_1 = dd.ct_files[1].dcms[1]
    hausdorff_weights = (ct_1.PixelSpacing..., ct_1.SliceThickness)

    for (roi_name, roi_mask) in dd.roi_masks

        fprs = zeros(N)
        fnrs = zeros(N)
        dcs = zeros(N)
        hausd = zeros(N)
        #println("ROI: ", roi_name)
        mask_inds = findall(vec(roi_mask))
        for i in 1:length(q)
            level = q[i]
            cm = confusion_matrix_at_level(dd.doses, dd.primo_filtered_in_Gy, mask_inds, level)
            fprs[i] = cm.fp / (cm.fp + cm.tn)
            fnrs[i] = cm.fn / (cm.fn + cm.tp)
            dcs[i] = 2 * cm.tp / (2 * cm.tp + cm.fp + cm.fn)
            if hausdorff_weights isa NTuple{3,Real}
                hausd[i] = hausdorff_distance(dd.doses, dd.primo_filtered_in_Gy, roi_mask, hausdorff_weights, level)
            end
            #println("h for level $level =", hausd[i])
        end
        #println("")

        fq_TPS = calc_dvh_for_doses(q, dd.doses[roi_mask])
        fq_Primo = calc_dvh_for_doses(q, dd.primo_filtered_in_Gy[roi_mask])

        roi_to_plotdata[roi_name] = (; DVH_TPS = fq_TPS, DVH_Primo = fq_Primo, fpr = fprs, fnr = fnrs, dice = dcs, hausd = hausd)
    end

    return (q, roi_to_plotdata)
end

# modalities:
# RTDOSE: planned dose distribution
# CT: CT scan
# RTSTRUCT: structures in the CT scan

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
    ct_mesh_from_files(dd::DoseData, ct_mesh_fname; kwargs...)

Make a CT mesh from the given `DoseData` object and save the result to file `ct_mesh_fname`.
The extension part of `ct_mesh_fname` file must be one of the formats supported by MeshIO.
`.obj` is preferred.

Given `kwargs` are passed to `make_CT_mesh`.

# Example

`ct_mesh_from_files(dd, "/tmp/test.obj"; isolevel=1000.0)`
"""
function create_mesh_and_save(dd::DoseData, save_to; kwargs...)
    ct_mesh = make_CT_mesh(dd.ct_files; kwargs...)
    save(save_to, ct_mesh)
    return save_to
end


"""
    make_ROI_mesh(dd::DoseData, roi_name, roi_mesh_fname)
Prepare mesh of ROI boundary for for the region of name `roi_name`. The mesh is saved in
file `roi_mesh_fname`.
"""
function make_ROI_mesh(dd::DoseData, roi_name, roi_mesh_fname)
    algo_roi = NaiveSurfaceNets(iso = 0.5, insidepositive = true)
    origin, widths = ct_origin_widths(dd.ct_files)
    roi_mesh = make_normals(convert(Array{Float32}, dd.roi_masks[roi_name]), algo_roi, origin, widths)
    save(roi_mesh_fname, roi_mesh)
    return roi_mesh_fname
end

