# PreScanNormalization
小池研のフォルダ構成において、codeフォルダ内にスクリプトを置いてください。
Pre-freesuferferが処理済みのSubjectにおいて、sourcedataおよびderivatives/HCPpipelineのデータを参照して、Pre ScanNormalizationを行います。
中間ファイルは、/derivatives/PreScanNomalization/${SubjID}に作成されます。
sourcedataのNomalization前のファイルはNotNorm.nii.gzにリメームされ、Normalize後のファイルは元のsourcedata下の該当ファイルに置き換えられます。
