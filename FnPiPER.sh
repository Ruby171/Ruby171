#!/bin/bash

# set pd
pd=$(pwd)

# define functions
source .build/scripts/functions.sh

# make config.txt (if needed)
if ! [ -f config.txt ]
then
    source .build/scripts/setup/makeConfig.sh
    exit
else
    read -rp "Config file exists. Is it up to date? [y/n]: " -n 1
    echo ""
    if ! [[ ${REPLY} =~ ^[Yy]$ ]]
    then
		echo "Check config file, make sure it's up to date."
		echo "Exiting script."
		exit
	fi
fi

# Scrape value from config file
scrapeConfig

# check conda environments
if ${doCheckCondaEnvs}
then
    source .build/scripts/setup/checkCondaEnvs.sh
fi

# build project directory structure
if ! [ -f FnPiPER.slurm ]
then
	# Make files/ and working/ as needed
	checkDir files
	checkDir working/output/mosdepth
	checkDir working/output/pixy
	checkDir working/reads/clean/fastqc
	checkDir working/reads/raw

	# Remove specified files as needed
	rmFile FnPiPER.slurm
	rmFile files/list.txt
	rmFile files/names.txt
	rmFile files/bamlist.txt
	rmFile files/windowSizes.txt

	# Copy FnPiPER
	cp .build/FnPiPER.slurm ./

	# Copy scripts/ if needed
	if ! [ -d scripts ]
	then
		cp -r .build/scripts/ ./
	fi

	# Generate files (list.txt, names.txt, bamlist.txt)
	for file in *_1.fastq.gz
	do
		# Get sample name (ID_Sex) from filename
		id=$(echo ${file} | cut -d "_" -f 3)
		sex=$(echo ${file} | cut -d "_" -f 4)

		sample_name="${id}_${sex}"

		# list.txt
		echo "${sample_name}" >> files/list.txt

		# bamlist.txt
		echo "${pd}/working/${sample_name}.rg.bam" >> files/bamlist.txt

		# names.txt
		echo -e "${sample_name}\t${sex}" >> files/names.txt
	done

	# Get window sizes
	for size in $(grep "^window_size:" config.txt | cut -d ":" -f 2)
	do
	    echo ${size} >> files/windowSizes.txt
	done

	# Substitute placeholders for values
	sed -i "s|__TOTAL_HOURS__|${total_hours}|" FnPiPER.slurm
	sed -i "s|__EMAIL__|${email}|" FnPiPER.slurm
	sed -i "s|__PD__|${pd}|" FnPiPER.slurm

	# Sample names & IDs (when needed) to templates
	for template in scripts/templates/template_*
	do
		# Get template name
		filename=$(basename ${template} .sh)

		# Get job name
		name=$(echo ${filename} | cut -d "_" -f 2)

		# Replace constant placeholders
		sed -i "s|__PD__|${pd}|" ${template}
		sed -i "s|__NAME__|${name}|" ${template}
	    sed -i "s|__EMAIL__|${email}|" ${template}
	    sed -i "s|__GENUS__|${genus}|" ${template}
	    sed -i "s|__GENOME__|${genome}|" ${template}
	    sed -i "s|__SPECIES__|${species}|" ${template}

		# Replace ID placeholders
		if [ ${name} == "cleanReads" ] || \
		[ ${name} == "mapReads" ] || \
		[ ${name} == "mosdepth" ]
		then
			while read -r id
			do
				# cd into scripts
				cd ${pd}/scripts

				# set script name
				script_name="${name}_${id}.slurm"

				# copy template
				cp templates/${filename}.sh ${script_name}

				# replace placeholders
				sed -i "s|__ID__|${id}|" ${script_name}

				# make job subdirectory (if needed)
				checkDir ${name}

				# move script into subdirectory
				mv ${script_name} ${name}

				# cd back out
				cd ${pd}
			done < ${pd}/files/list.txt
		elif [ ${name} == "freebayes" ] || \
		[ ${name} == "indexReferenceGenome" ] || \
		[ ${name} == "pixyStats" ]
		then
			# cd into scripts
			cd ${pd}/scripts

			# set script name
			script_name="${name}.slurm"

			# copy template
			cp templates/${filename}.sh ${script_name}

			# replace placeholders
			if [ ${name} == "freebayes" ]
			then
				sed -i "s|__FB_HOURS__|${freebayes_hours}|" ${script_name}
			fi

			# make job subdirectory (if needed)
			checkDir ${name}

			# move script into subdirectory
			mv ${script_name} ${name}

			# cd back out
			cd ${pd}
		fi
	done

	# Move files
	if [ -f genome_*.fasta ]
	then
		mv genome_*.fasta working/
	fi

	if [[ -f $(ls *_1.fastq.gz | head -n 1) ]] && [[ -f $(ls *_2.fastq.gz | head -n 1) ]]
	then
		mv *.fastq.gz working/reads/raw
	fi
fi

# submit job
if ${doSubmit}
then
    cd ${pd}

	# make log
	makeLog

	# replace __LOG__ in FnPiPER.slurm
	sed -i "s|__LOG__|${log}|" FnPiPER.slurm

	# submit
    sbatch FnPiPER.slurm
fi
