#! /bin/bash
# set output directory
export HCPPIPEDIR=/usr/local/HCPpipelines
source $HCPPIPEDIR/SetUpHCPPipeline.sh
expr "${0}" : "/.*" > /dev/null || cwd=`(cd "${cwd}" && pwd)`
RootDir=${cwd%/code*}
echo ${RootDir}
TmpDir=${RootDir}/Templates
StudyFolder=${RootDir}/derivatives/HCPpipeline
PreScanNormFolder=${RootDir}/derivatives/PreScanNromalize
if [ ! -d $PreScanNormFolder ];then
  mkdir $PreScanNormFolder
fi


Subject=$(basename $1)
SouceDir=${RootDir}/sourcedata/${Subject}/

T2wNotNrom=${SouceDir}/anat/${Subject}_notNORM_T2w.nii.gz
GradientDistortionCoeffs=${RootDir}/code/SimensPrismaKomaba_coeff.grad

# for Spin Echo fieldmap
SEEchoSpacing="0.00058"
# z appears to be the appropriate polarity for the 3D structurals collected on Siemens scanners
# AP/PA = y-/y  RL/LR =z-/z
#UnwarpDir="z"
PhaseDir="y-" #T ishida used y-





TagFiles=()
#Add filedmap
#runs=("" "_run-01" "_run-02" "_run-03" "_run-04" "_run-05" )
#for run in "${runs[@]}" ; do
#	if [  -f ${SouceDir}/fmap/${Subject}_dir-AP${run}_epi.nii.gz ];then 
#		TagFiles+=(${SouceDir}/fmap/${Subject}_dir-AP${run}_epi.nii.gz)
#	fi
#	if [  -f ${SouceDir}/fmap/${Subject}_dir-PA${run}_epi.nii.gz ];then 
#		TagFiles+=(${SouceDir}/fmap/${Subject}_dir-PA${run}_epi.nii.gz)
#	fi
#done
 
#Add dwi
#dwi_post=("_acq-107axis_dir-PA_dwi.nii.gz" "_acq-107axis_dir-AP_dwi.nii.gz" "_acq-99axis_dir-PA_dwi.nii.gz" "_acq-99axis_dir-AP_dwi.nii.gz")
dwi_post=("_acq-99axis_dir-PA_dwi.nii.gz" "_acq-99axis_dir-AP_dwi.nii.gz")

for post in "${dwi_post[@]}" ; do
	if [  -f ${SouceDir}/dwi/${Subject}${post} ];then 
		TagFiles+=(${SouceDir}/dwi/${Subject}${post})
	fi
done




# Other variables
DisCorrectDir=${StudyFolder}/${Subject}/T2w/T2wToT1wDistortionCorrectAndReg



# Run
if [[ $PhaseDir =~ "-" ]] ; then
	WarpDir=$(echo $PhaseDir | sed -e 's/-//g')
else
	WarpDir=$(echo ${PhaseDir}-)
fi


WorkingDir=${PreScanNormFolder}/${Subject}
if [ ! -d $WorkingDir ];then
  mkdir $WorkingDir
fi

## Gradient unwarp T2w_UnNorm
GradUnwarpDir=${WorkingDir}/T2w_UnNorm_GradientDistortionUnwarp
mkdir -p ${GradUnwarpDir}
${FSLDIR}/bin/fslreorient2std $T2wNotNrom ${GradUnwarpDir}/T2w_UnNorm
${HCPPIPEDIR}/global/scripts/GradientDistortionUnwarp.sh --workindir=${GradUnwarpDir} --coeffs=${GradientDistortionCoeffs} --in=${GradUnwarpDir}/T2w_UnNorm --out=${GradUnwarpDir}/T2w_UnNorm_gdc.nii.gz --owarp=${GradUnwarpDir}/T2w_UnNorm_gdc_warp.nii.gz
imcp ${GradUnwarpDir}/T2w_UnNorm_gdc.nii.gz  ${WorkingDir}/T2w_UnNorm
##else
## ${FSLDIR}/bin/fslreorient2std $T2w_UnNorm ${WorkingDir}/T2w_UnNorm


## Create normalize coefficient
${FSLDIR}/bin/applywarp -i ${WorkingDir}/T2w_UnNorm --premat=${StudyFolder}/${Subject}/T2w/xfms/acpc.mat  -r ${DisCorrectDir}/T2w_acpc.nii.gz -o ${WorkingDir}/T2w_UnNorm_acpc
${FSLDIR}/bin/fslmaths ${DisCorrectDir}/T2w_acpc  -div ${WorkingDir}/T2w_UnNorm_acpc -mas ${DisCorrectDir}/T2w_acpc_brain -dilall -s 5 ${WorkingDir}/Normalize_acpc
${FSLDIR}/bin/convert_xfm -omat ${WorkingDir}/T2w_acpc2Fieldmap.mat -inverse ${DisCorrectDir}/Fieldmap2T2w_acpc.mat


# Target brain extraction
for Tagfile in "${TagFiles[@]}" ; do
	echo "Prescan Normalize on ${Tagfile}"
	Target=$(remove_ext $(basename $Tagfile));
	TargetImage=${WorkingDir}/${Target}

	# Target brain extraction
	${FSLDIR}/bin/fslroi ${Tagfile} ${TargetImage} 0 1
	${FSLDIR}/bin/bet ${TargetImage} ${TargetImage}_brain -f 0.3
		
	# Forward warping fieldmap and magnitude
	${FSLDIR}/bin/fugue --loadfmap=${DisCorrectDir}/FieldMap --dwell=${SEEchoSpacing} --saveshift=${WorkingDir}/FieldMap_ShiftMap${Target}.nii.gz
	${FSLDIR}/bin/convertwarp --relout --rel --ref=${DisCorrectDir}/Magnitude --shiftmap=${WorkingDir}/FieldMap_ShiftMap${Target}.nii.gz --shiftdir=${WarpDir} --out=${WorkingDir}/FieldMap_Warp${Target}.nii.gz
	${FSLDIR}/bin/applywarp --rel --interp=spline -i ${DisCorrectDir}/Magnitude_brain -r ${DisCorrectDir}/Magnitude_brain -w ${WorkingDir}/FieldMap_Warp${Target}.nii.gz -o ${WorkingDir}/Magnitude_brain_warped${Target}

	# Register distorted mag to target
	${FSLDIR}/bin/flirt -interp spline -dof 6 -in ${WorkingDir}/Magnitude_brain_warped${Target} -ref ${TargetImage}_brain -out ${WorkingDir}/Magnitude_brain_warped${Target}_postreg -omat ${WorkingDir}/Fieldmap2${Target}.mat -searchrx -30 30 -searchry -30 30 -searchrz -30 30

	# Combine warp
	${FSLDIR}/bin/convertwarp --relout --rel --ref=${TargetImage} --premat=${WorkingDir}/T2w_acpc2Fieldmap.mat -w ${WorkingDir}/FieldMap_Warp${Target} --postmat=${WorkingDir}/Fieldmap2${Target}.mat -o ${WorkingDir}/FieldMap_Warp${Target}_postreg -j ${WorkingDir}/FieldMap_Warp${Target}_postreg_jac
	${FSLDIR}/bin/fslmaths ${WorkingDir}/FieldMap_Warp${Target}_postreg_jac -Tmean ${WorkingDir}/FieldMap_Warp${Target}_postreg_jac

	# Apply warp to normalize coefficinet
	${FSLDIR}/bin/applywarp --rel --interp=spline -i ${WorkingDir}/Normalize_acpc -w ${WorkingDir}/FieldMap_Warp${Target}_postreg -r ${TargetImage} -o ${WorkingDir}/Normalize2${Target}
	${FSLDIR}/bin/fslmaths ${WorkingDir}/Normalize2${Target} -mul ${WorkingDir}/FieldMap_Warp${Target}_postreg_jac ${WorkingDir}/Normalize2${Target}_jac # jac seems not useful 

	# Normalize target volume
	${FSLDIR}/bin/fslmaths ${Tagfile} -mul ${WorkingDir}/Normalize2${Target} ${WorkingDir}/${Target}_Norm

	cp ${Tagfile} $(remove_ext ${Tagfile})_NotNorm.nii.gz
	cp ${WorkingDir}/${Target}_Norm.nii.gz ${Tagfile} 

	
done