#!/bin/bash
#SBATCH --job-name=check
#SBATCH --output=logs/check_%j.out
#SBATCH --partition=u1-compute
#SBATCH --account=@[CPU_ACCNR]
#SBATCH --nodes=1
#SBATCH --ntasks-per-node=1
#SBATCH --cpus-per-task=1
#SBATCH --time=@[CHECK_WALLTIME]

# set vars
INIT_TIME="@[INIT_TIME]"
LEAD_HOUR=@[LEAD_HOUR]
N_ENSEMBLES=@[N_ENSEMBLES]
PACKAGEROOT=@[PACKAGEROOT]
DATAROOT=@[DATAROOT]

# extract date and hour
DATE=${INIT_TIME%%T*}
DATE=${DATE//-/}
HOUR=${INIT_TIME#*T}

CYCLE_DIR="${DATAROOT}/${DATE}/${HOUR}"
FAILED_LIST="${DATAROOT}/failed_runs.txt"

echo "In check, init_time=${INIT_TIME}, cycle_dir=${CYCLE_DIR}, members=${N_ENSEMBLES}, lead=${LEAD_HOUR}"

# Expected products: member mNN, lead f00..fLEAD, for the cycle hour tHHz.
missing=0
missing_files=()
for (( m=0; m<N_ENSEMBLES; m++ )); do
    mm=$(printf "%02d" "$m")
    for (( f=0; f<=LEAD_HOUR; f++ )); do
        ff=$(printf "%02d" "$f")
        file="${CYCLE_DIR}/hrrrcast.m${mm}.t${HOUR}z.pgrb2.f${ff}"
        # -s: exists AND non-empty (catches truncated/zero-byte files too)
        if [[ ! -s "$file" ]]; then
            missing=$((missing+1))
            missing_files+=( "$(basename "$file")" )
        fi
    done
done

expected=$(( N_ENSEMBLES * (LEAD_HOUR + 1) ))
present=$(( expected - missing ))
echo "Expected ${expected} files, present ${present}, missing ${missing}"

if (( missing > 0 )); then
    echo "INCOMPLETE run ${INIT_TIME}: ${missing} missing file(s):"
    printf '  %s\n' "${missing_files[@]}"
    # Record the init time in the failed-runs list. flock serializes concurrent
    # cycles; grep -qxF avoids duplicate entries on re-runs.
    (
        flock 200
        grep -qxF "${INIT_TIME}" "${FAILED_LIST}" 2>/dev/null || echo "${INIT_TIME}" >> "${FAILED_LIST}"
    ) 200>"${FAILED_LIST}.lock"
    echo "Recorded ${INIT_TIME} in ${FAILED_LIST}"
    exit 1
fi

echo "Run ${INIT_TIME} complete — all ${expected} products present."#!/bin/bash
#SBATCH --job-name=check
#SBATCH --output=logs/check_%j.out
#SBATCH --partition=u1-compute
#SBATCH --account=@[CPU_ACCNR]
#SBATCH --nodes=1
#SBATCH --ntasks-per-node=1
#SBATCH --cpus-per-task=1
#SBATCH --time=@[CHECK_WALLTIME]

# set vars
INIT_TIME="@[INIT_TIME]"
LEAD_HOUR=@[LEAD_HOUR]
N_ENSEMBLES=@[N_ENSEMBLES]
PACKAGEROOT=@[PACKAGEROOT]
DATAROOT=@[DATAROOT]

# extract date and hour
DATE=${INIT_TIME%%T*}
DATE=${DATE//-/}
HOUR=${INIT_TIME#*T}

CYCLE_DIR="${DATAROOT}/${DATE}/${HOUR}"
FAILED_LIST="${DATAROOT}/failed_runs.txt"

echo "In check, init_time=${INIT_TIME}, cycle_dir=${CYCLE_DIR}, members=${N_ENSEMBLES}, lead=${LEAD_HOUR}"

# Expected products: member mNN, lead f00..fLEAD, for the cycle hour tHHz.
missing=0
missing_files=()
for (( m=0; m<N_ENSEMBLES; m++ )); do
	    mm=$(printf "%02d" "$m")
	        for (( f=0; f<=LEAD_HOUR; f++ )); do
			        ff=$(printf "%02d" "$f")
				        file="${CYCLE_DIR}/hrrrcast.m${mm}.t${HOUR}z.pgrb2.f${ff}"
					        # -s: exists AND non-empty (catches truncated/zero-byte files too)
						        if [[ ! -s "$file" ]]; then
								            missing=$((missing+1))
									                missing_files+=( "$(basename "$file")" )
											        fi
												    done
											    done

											    expected=$(( N_ENSEMBLES * (LEAD_HOUR + 1) ))
											    present=$(( expected - missing ))
											    echo "Expected ${expected} files, present ${present}, missing ${missing}"

											    if (( missing > 0 )); then
												        echo "INCOMPLETE run ${INIT_TIME}: ${missing} missing file(s):"
													    printf '  %s\n' "${missing_files[@]}"
													        # Record the init time in the failed-runs list. flock serializes concurrent
														    # cycles; grep -qxF avoids duplicate entries on re-runs.
														        (
															        flock 200
																        grep -qxF "${INIT_TIME}" "${FAILED_LIST}" 2>/dev/null || echo "${INIT_TIME}" >> "${FAILED_LIST}"
																	    ) 200>"${FAILED_LIST}.lock"
																	        echo "Recorded ${INIT_TIME} in ${FAILED_LIST}"
																		    exit 1
											    fi

											    echo "Run ${INIT_TIME} complete — all ${expected} products present."#!/bin/bash
											    #SBATCH --job-name=check
											    #SBATCH --output=logs/check_%j.out
											    #SBATCH --partition=u1-compute
											    #SBATCH --account=@[CPU_ACCNR]
											    #SBATCH --nodes=1
											    #SBATCH --ntasks-per-node=1
											    #SBATCH --cpus-per-task=1
											    #SBATCH --time=@[CHECK_WALLTIME]

											    # set vars
											    INIT_TIME="@[INIT_TIME]"
											    LEAD_HOUR=@[LEAD_HOUR]
											    N_ENSEMBLES=@[N_ENSEMBLES]
											    PACKAGEROOT=@[PACKAGEROOT]
											    DATAROOT=@[DATAROOT]

											    # extract date and hour
											    DATE=${INIT_TIME%%T*}
											    DATE=${DATE//-/}
											    HOUR=${INIT_TIME#*T}

											    CYCLE_DIR="${DATAROOT}/${DATE}/${HOUR}"
											    FAILED_LIST="${DATAROOT}/failed_runs.txt"

											    echo "In check, init_time=${INIT_TIME}, cycle_dir=${CYCLE_DIR}, members=${N_ENSEMBLES}, lead=${LEAD_HOUR}"

											    # Expected products: member mNN, lead f00..fLEAD, for the cycle hour tHHz.
											    missing=0
											    missing_files=()
											    for (( m=0; m<N_ENSEMBLES; m++ )); do
												        mm=$(printf "%02d" "$m")
													    for (( f=0; f<=LEAD_HOUR; f++ )); do
														            ff=$(printf "%02d" "$f")
															            file="${CYCLE_DIR}/hrrrcast.m${mm}.t${HOUR}z.pgrb2.f${ff}"
																            # -s: exists AND non-empty (catches truncated/zero-byte files too)
																	            if [[ ! -s "$file" ]]; then
																			                missing=$((missing+1))
																					            missing_files+=( "$(basename "$file")" )
																						            fi
																							        done
																							done

																							expected=$(( N_ENSEMBLES * (LEAD_HOUR + 1) ))
																							present=$(( expected - missing ))
																							echo "Expected ${expected} files, present ${present}, missing ${missing}"

																							if (( missing > 0 )); then
																								    echo "INCOMPLETE run ${INIT_TIME}: ${missing} missing file(s):"
																								        printf '  %s\n' "${missing_files[@]}"
																									    # Record the init time in the failed-runs list. flock serializes concurrent
																									        # cycles; grep -qxF avoids duplicate entries on re-runs.
																										    (
																										            flock 200
																											            grep -qxF "${INIT_TIME}" "${FAILED_LIST}" 2>/dev/null || echo "${INIT_TIME}" >> "${FAILED_LIST}"
																												        ) 200>"${FAILED_LIST}.lock"
																													    echo "Recorded ${INIT_TIME} in ${FAILED_LIST}"
																													        exit 1
																							fi

																							echo "Run ${INIT_TIME} complete — all ${expected} products present."#!/bin/bash
																							#SBATCH --job-name=check
																							#SBATCH --output=logs/check_%j.out
																							#SBATCH --partition=u1-compute
																							#SBATCH --account=@[CPU_ACCNR]
																							#SBATCH --nodes=1
																							#SBATCH --ntasks-per-node=1
																							#SBATCH --cpus-per-task=1
																							#SBATCH --time=@[CHECK_WALLTIME]

																							# set vars
																							INIT_TIME="@[INIT_TIME]"
																							LEAD_HOUR=@[LEAD_HOUR]
																							N_ENSEMBLES=@[N_ENSEMBLES]
																							PACKAGEROOT=@[PACKAGEROOT]
																							DATAROOT=@[DATAROOT]

																							# extract date and hour
																							DATE=${INIT_TIME%%T*}
																							DATE=${DATE//-/}
																							HOUR=${INIT_TIME#*T}

																							CYCLE_DIR="${DATAROOT}/${DATE}/${HOUR}"
																							FAILED_LIST="${DATAROOT}/failed_runs.txt"

																							echo "In check, init_time=${INIT_TIME}, cycle_dir=${CYCLE_DIR}, members=${N_ENSEMBLES}, lead=${LEAD_HOUR}"

																							# Expected products: member mNN, lead f00..fLEAD, for the cycle hour tHHz.
																							missing=0
																							missing_files=()
																							for (( m=0; m<N_ENSEMBLES; m++ )); do
																								    mm=$(printf "%02d" "$m")
																								        for (( f=0; f<=LEAD_HOUR; f++ )); do
																										        ff=$(printf "%02d" "$f")
																											        file="${CYCLE_DIR}/hrrrcast.m${mm}.t${HOUR}z.pgrb2.f${ff}"
																												        # -s: exists AND non-empty (catches truncated/zero-byte files too)
																													        if [[ ! -s "$file" ]]; then
																															            missing=$((missing+1))
																																                missing_files+=( "$(basename "$file")" )
																																		        fi
																																			    done
																																		    done

																																		    expected=$(( N_ENSEMBLES * (LEAD_HOUR + 1) ))
																																		    present=$(( expected - missing ))
																																		    echo "Expected ${expected} files, present ${present}, missing ${missing}"

																																		    if (( missing > 0 )); then
																																			        echo "INCOMPLETE run ${INIT_TIME}: ${missing} missing file(s):"
																																				    printf '  %s\n' "${missing_files[@]}"
																																				        # Record the init time in the failed-runs list. flock serializes concurrent
																																					    # cycles; grep -qxF avoids duplicate entries on re-runs.
																																					        (
																																						        flock 200
																																							        grep -qxF "${INIT_TIME}" "${FAILED_LIST}" 2>/dev/null || echo "${INIT_TIME}" >> "${FAILED_LIST}"
																																								    ) 200>"${FAILED_LIST}.lock"
																																								        echo "Recorded ${INIT_TIME} in ${FAILED_LIST}"
																																									    exit 1
																																		    fi

																																		    echo "Run ${INIT_TIME} complete — all ${expected} products present."#!/bin/bash
																																		    #SBATCH --job-name=check
																																		    #SBATCH --output=logs/check_%j.out
																																		    #SBATCH --partition=u1-compute
																																		    #SBATCH --account=@[CPU_ACCNR]
																																		    #SBATCH --nodes=1
																																		    #SBATCH --ntasks-per-node=1
																																		    #SBATCH --cpus-per-task=1
																																		    #SBATCH --time=@[CHECK_WALLTIME]

																																		    # set vars
																																		    INIT_TIME="@[INIT_TIME]"
																																		    LEAD_HOUR=@[LEAD_HOUR]
																																		    N_ENSEMBLES=@[N_ENSEMBLES]
																																		    PACKAGEROOT=@[PACKAGEROOT]
																																		    DATAROOT=@[DATAROOT]

																																		    # extract date and hour
																																		    DATE=${INIT_TIME%%T*}
																																		    DATE=${DATE//-/}
																																		    HOUR=${INIT_TIME#*T}

																																		    CYCLE_DIR="${DATAROOT}/${DATE}/${HOUR}"
																																		    FAILED_LIST="${DATAROOT}/failed_runs.txt"

																																		    echo "In check, init_time=${INIT_TIME}, cycle_dir=${CYCLE_DIR}, members=${N_ENSEMBLES}, lead=${LEAD_HOUR}"

																																		    # Expected products: member mNN, lead f00..fLEAD, for the cycle hour tHHz.
																																		    missing=0
																																		    missing_files=()
																																		    for (( m=0; m<N_ENSEMBLES; m++ )); do
																																			        mm=$(printf "%02d" "$m")
																																				    for (( f=0; f<=LEAD_HOUR; f++ )); do
																																					            ff=$(printf "%02d" "$f")
																																						            file="${CYCLE_DIR}/hrrrcast.m${mm}.t${HOUR}z.pgrb2.f${ff}"
																																							            # -s: exists AND non-empty (catches truncated/zero-byte files too)
																																								            if [[ ! -s "$file" ]]; then
																																										                missing=$((missing+1))
																																												            missing_files+=( "$(basename "$file")" )
																																													            fi
																																														        done
																																														done

																																														expected=$(( N_ENSEMBLES * (LEAD_HOUR + 1) ))
																																														present=$(( expected - missing ))
																																														echo "Expected ${expected} files, present ${present}, missing ${missing}"

																																														if (( missing > 0 )); then
																																															    echo "INCOMPLETE run ${INIT_TIME}: ${missing} missing file(s):"
																																															        printf '  %s\n' "${missing_files[@]}"
																																																    # Record the init time in the failed-runs list. flock serializes concurrent
																																																        # cycles; grep -qxF avoids duplicate entries on re-runs.
																																																	    (
																																																	            flock 200
																																																		            grep -qxF "${INIT_TIME}" "${FAILED_LIST}" 2>/dev/null || echo "${INIT_TIME}" >> "${FAILED_LIST}"
																																																			        ) 200>"${FAILED_LIST}.lock"
																																																				    echo "Recorded ${INIT_TIME} in ${FAILED_LIST}"
																																																				        exit 1
																																														fi

																																														echo "Run ${INIT_TIME} complete — all ${expected} products present."#!/bin/bash
																																														#SBATCH --job-name=check
																																														#SBATCH --output=logs/check_%j.out
																																														#SBATCH --partition=u1-compute
																																														#SBATCH --account=@[CPU_ACCNR]
																																														#SBATCH --nodes=1
																																														#SBATCH --ntasks-per-node=1
																																														#SBATCH --cpus-per-task=1
																																														#SBATCH --time=@[CHECK_WALLTIME]

																																														# set vars
																																														INIT_TIME="@[INIT_TIME]"
																																														LEAD_HOUR=@[LEAD_HOUR]
																																														N_ENSEMBLES=@[N_ENSEMBLES]
																																														PACKAGEROOT=@[PACKAGEROOT]
																																														DATAROOT=@[DATAROOT]

																																														# extract date and hour
																																														DATE=${INIT_TIME%%T*}
																																														DATE=${DATE//-/}
																																														HOUR=${INIT_TIME#*T}

																																														CYCLE_DIR="${DATAROOT}/${DATE}/${HOUR}"
																																														FAILED_LIST="${DATAROOT}/failed_runs.txt"

																																														echo "In check, init_time=${INIT_TIME}, cycle_dir=${CYCLE_DIR}, members=${N_ENSEMBLES}, lead=${LEAD_HOUR}"

																																														# Expected products: member mNN, lead f00..fLEAD, for the cycle hour tHHz.
																																														missing=0
																																														missing_files=()
																																														for (( m=0; m<N_ENSEMBLES; m++ )); do
																																															    mm=$(printf "%02d" "$m")
																																															        for (( f=0; f<=LEAD_HOUR; f++ )); do
																																																	        ff=$(printf "%02d" "$f")
																																																		        file="${CYCLE_DIR}/hrrrcast.m${mm}.t${HOUR}z.pgrb2.f${ff}"
																																																			        # -s: exists AND non-empty (catches truncated/zero-byte files too)
																																																				        if [[ ! -s "$file" ]]; then
																																																						            missing=$((missing+1))
																																																							                missing_files+=( "$(basename "$file")" )
																																																									        fi
																																																										    done
																																																									    done

																																																									    expected=$(( N_ENSEMBLES * (LEAD_HOUR + 1) ))
																																																									    present=$(( expected - missing ))
																																																									    echo "Expected ${expected} files, present ${present}, missing ${missing}"

																																																									    if (( missing > 0 )); then
																																																										        echo "INCOMPLETE run ${INIT_TIME}: ${missing} missing file(s):"
																																																											    printf '  %s\n' "${missing_files[@]}"
																																																											        # Record the init time in the failed-runs list. flock serializes concurrent
																																																												    # cycles; grep -qxF avoids duplicate entries on re-runs.
																																																												        (
																																																													        flock 200
																																																														        grep -qxF "${INIT_TIME}" "${FAILED_LIST}" 2>/dev/null || echo "${INIT_TIME}" >> "${FAILED_LIST}"
																																																															    ) 200>"${FAILED_LIST}.lock"
																																																															        echo "Recorded ${INIT_TIME} in ${FAILED_LIST}"
																																																																    exit 1
																																																									    fi

																																																									    echo "Run ${INIT_TIME} complete — all ${expected} products present."#!/bin/bash
																																																									    #SBATCH --job-name=check
																																																									    #SBATCH --output=logs/check_%j.out
																																																									    #SBATCH --partition=u1-compute
																																																									    #SBATCH --account=@[CPU_ACCNR]
																																																									    #SBATCH --nodes=1
																																																									    #SBATCH --ntasks-per-node=1
																																																									    #SBATCH --cpus-per-task=1
																																																									    #SBATCH --time=@[CHECK_WALLTIME]

																																																									    # set vars
																																																									    INIT_TIME="@[INIT_TIME]"
																																																									    LEAD_HOUR=@[LEAD_HOUR]
																																																									    N_ENSEMBLES=@[N_ENSEMBLES]
																																																									    PACKAGEROOT=@[PACKAGEROOT]
																																																									    DATAROOT=@[DATAROOT]

																																																									    # extract date and hour
																																																									    DATE=${INIT_TIME%%T*}
																																																									    DATE=${DATE//-/}
																																																									    HOUR=${INIT_TIME#*T}

																																																									    CYCLE_DIR="${DATAROOT}/${DATE}/${HOUR}"
																																																									    FAILED_LIST="${DATAROOT}/failed_runs.txt"

																																																									    echo "In check, init_time=${INIT_TIME}, cycle_dir=${CYCLE_DIR}, members=${N_ENSEMBLES}, lead=${LEAD_HOUR}"

																																																									    # Expected products: member mNN, lead f00..fLEAD, for the cycle hour tHHz.
																																																									    missing=0
																																																									    missing_files=()
																																																									    for (( m=0; m<N_ENSEMBLES; m++ )); do
																																																										        mm=$(printf "%02d" "$m")
																																																											    for (( f=0; f<=LEAD_HOUR; f++ )); do
																																																												            ff=$(printf "%02d" "$f")
																																																													            file="${CYCLE_DIR}/hrrrcast.m${mm}.t${HOUR}z.pgrb2.f${ff}"
																																																														            # -s: exists AND non-empty (catches truncated/zero-byte files too)
																																																															            if [[ ! -s "$file" ]]; then
																																																																	                missing=$((missing+1))
																																																																			            missing_files+=( "$(basename "$file")" )
																																																																				            fi
																																																																					        done
																																																																					done

																																																																					expected=$(( N_ENSEMBLES * (LEAD_HOUR + 1) ))
																																																																					present=$(( expected - missing ))
																																																																					echo "Expected ${expected} files, present ${present}, missing ${missing}"

																																																																					if (( missing > 0 )); then
																																																																						    echo "INCOMPLETE run ${INIT_TIME}: ${missing} missing file(s):"
																																																																						        printf '  %s\n' "${missing_files[@]}"
																																																																							    # Record the init time in the failed-runs list. flock serializes concurrent
																																																																							        # cycles; grep -qxF avoids duplicate entries on re-runs.
																																																																								    (
																																																																								            flock 200
																																																																									            grep -qxF "${INIT_TIME}" "${FAILED_LIST}" 2>/dev/null || echo "${INIT_TIME}" >> "${FAILED_LIST}"
																																																																										        ) 200>"${FAILED_LIST}.lock"
																																																																											    echo "Recorded ${INIT_TIME} in ${FAILED_LIST}"
																																																																											        exit 1
																																																																					fi

																																																																					echo "Run ${INIT_TIME} complete — all ${expected} products present."#!/bin/bash
																																																																					#SBATCH --job-name=check
																																																																					#SBATCH --output=logs/check_%j.out
																																																																					#SBATCH --partition=u1-compute
																																																																					#SBATCH --account=@[CPU_ACCNR]
																																																																					#SBATCH --nodes=1
																																																																					#SBATCH --ntasks-per-node=1
																																																																					#SBATCH --cpus-per-task=1
																																																																					#SBATCH --time=@[CHECK_WALLTIME]

																																																																					# set vars
																																																																					INIT_TIME="@[INIT_TIME]"
																																																																					LEAD_HOUR=@[LEAD_HOUR]
																																																																					N_ENSEMBLES=@[N_ENSEMBLES]
																																																																					PACKAGEROOT=@[PACKAGEROOT]
																																																																					DATAROOT=@[DATAROOT]

																																																																					# extract date and hour
																																																																					DATE=${INIT_TIME%%T*}
																																																																					DATE=${DATE//-/}
																																																																					HOUR=${INIT_TIME#*T}

																																																																					CYCLE_DIR="${DATAROOT}/${DATE}/${HOUR}"
																																																																					FAILED_LIST="${DATAROOT}/failed_runs.txt"

																																																																					echo "In check, init_time=${INIT_TIME}, cycle_dir=${CYCLE_DIR}, members=${N_ENSEMBLES}, lead=${LEAD_HOUR}"

																																																																					# Expected products: member mNN, lead f00..fLEAD, for the cycle hour tHHz.
																																																																					missing=0
																																																																					missing_files=()
																																																																					for (( m=0; m<N_ENSEMBLES; m++ )); do
																																																																						    mm=$(printf "%02d" "$m")
																																																																						        for (( f=0; f<=LEAD_HOUR; f++ )); do
																																																																								        ff=$(printf "%02d" "$f")
																																																																									        file="${CYCLE_DIR}/hrrrcast.m${mm}.t${HOUR}z.pgrb2.f${ff}"
																																																																										        # -s: exists AND non-empty (catches truncated/zero-byte files too)
																																																																											        if [[ ! -s "$file" ]]; then
																																																																													            missing=$((missing+1))
																																																																														                missing_files+=( "$(basename "$file")" )
																																																																																        fi
																																																																																	    done
																																																																																    done

																																																																																    expected=$(( N_ENSEMBLES * (LEAD_HOUR + 1) ))
																																																																																    present=$(( expected - missing ))
																																																																																    echo "Expected ${expected} files, present ${present}, missing ${missing}"

																																																																																    if (( missing > 0 )); then
																																																																																	        echo "INCOMPLETE run ${INIT_TIME}: ${missing} missing file(s):"
																																																																																		    printf '  %s\n' "${missing_files[@]}"
																																																																																		        # Record the init time in the failed-runs list. flock serializes concurrent
																																																																																			    # cycles; grep -qxF avoids duplicate entries on re-runs.
																																																																																			        (
																																																																																				        flock 200
																																																																																					        grep -qxF "${INIT_TIME}" "${FAILED_LIST}" 2>/dev/null || echo "${INIT_TIME}" >> "${FAILED_LIST}"
																																																																																						    ) 200>"${FAILED_LIST}.lock"
																																																																																						        echo "Recorded ${INIT_TIME} in ${FAILED_LIST}"
																																																																																							    exit 1
																																																																																    fi

																																																																																    echo "Run ${INIT_TIME} complete — all ${expected} products present."#!/bin/bash
																																																																																    #SBATCH --job-name=check
																																																																																    #SBATCH --output=logs/check_%j.out
																																																																																    #SBATCH --partition=u1-compute
																																																																																    #SBATCH --account=@[CPU_ACCNR]
																																																																																    #SBATCH --nodes=1
																																																																																    #SBATCH --ntasks-per-node=1
																																																																																    #SBATCH --cpus-per-task=1
																																																																																    #SBATCH --time=@[CHECK_WALLTIME]

																																																																																    # set vars
																																																																																    INIT_TIME="@[INIT_TIME]"
																																																																																    LEAD_HOUR=@[LEAD_HOUR]
																																																																																    N_ENSEMBLES=@[N_ENSEMBLES]
																																																																																    PACKAGEROOT=@[PACKAGEROOT]
																																																																																    DATAROOT=@[DATAROOT]

																																																																																    # extract date and hour
																																																																																    DATE=${INIT_TIME%%T*}
																																																																																    DATE=${DATE//-/}
																																																																																    HOUR=${INIT_TIME#*T}

																																																																																    CYCLE_DIR="${DATAROOT}/${DATE}/${HOUR}"
																																																																																    FAILED_LIST="${DATAROOT}/failed_runs.txt"

																																																																																    echo "In check, init_time=${INIT_TIME}, cycle_dir=${CYCLE_DIR}, members=${N_ENSEMBLES}, lead=${LEAD_HOUR}"

																																																																																    # Expected products: member mNN, lead f00..fLEAD, for the cycle hour tHHz.
																																																																																    missing=0
																																																																																    missing_files=()
																																																																																    for (( m=0; m<N_ENSEMBLES; m++ )); do
																																																																																	        mm=$(printf "%02d" "$m")
																																																																																		    for (( f=0; f<=LEAD_HOUR; f++ )); do
																																																																																			            ff=$(printf "%02d" "$f")
																																																																																				            file="${CYCLE_DIR}/hrrrcast.m${mm}.t${HOUR}z.pgrb2.f${ff}"
																																																																																					            # -s: exists AND non-empty (catches truncated/zero-byte files too)
																																																																																						            if [[ ! -s "$file" ]]; then
																																																																																								                missing=$((missing+1))
																																																																																										            missing_files+=( "$(basename "$file")" )
																																																																																											            fi
																																																																																												        done
																																																																																												done

																																																																																												expected=$(( N_ENSEMBLES * (LEAD_HOUR + 1) ))
																																																																																												present=$(( expected - missing ))
																																																																																												echo "Expected ${expected} files, present ${present}, missing ${missing}"

																																																																																												if (( missing > 0 )); then
																																																																																													    echo "INCOMPLETE run ${INIT_TIME}: ${missing} missing file(s):"
																																																																																													        printf '  %s\n' "${missing_files[@]}"
																																																																																														    # Record the init time in the failed-runs list. flock serializes concurrent
																																																																																														        # cycles; grep -qxF avoids duplicate entries on re-runs.
																																																																																															    (
																																																																																															            flock 200
																																																																																																            grep -qxF "${INIT_TIME}" "${FAILED_LIST}" 2>/dev/null || echo "${INIT_TIME}" >> "${FAILED_LIST}"
																																																																																																	        ) 200>"${FAILED_LIST}.lock"
																																																																																																		    echo "Recorded ${INIT_TIME} in ${FAILED_LIST}"
																																																																																																		        exit 1
																																																																																												fi

																																																																																												echo "Run ${INIT_TIME} complete — all ${expected} products present."
