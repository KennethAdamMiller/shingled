#!/bin/bash

analyze() {
    src=fns_large_top_500
    workdir="${1}${src}${3}_results"
    rm -rf "${workdir}"
    mkdir "${workdir}"
    echo "${1}"
    pushd "${workdir}"
    cat ../${src}.txt | while read f ; do   
        name="./$(basename "${f}").metrics"
        ~/workspace/superset_disassembler/superset_disasm.native --phases="${1}" --target="${f}" --ground_truth_bin="../$(basename "${f}")" --save_addrs --enable_feature="${2}" --rounds=2 --tp_threshold="${3}" >> "${name}"; 
        #~/workspace/binary_pgm/pgm_util.native --command=Disasm,"${1}" --rounds=1  >> "${name}"; 
    done
    popd
}

#j1= analyze "All Instruction invariants" "" "0.99"& 
#j2= analyze "Target_out_of_bounds" "" "0.99"& 
#j3= analyze "Target_is_bad" "" "0.99"& 
#j4= analyze "Invalid memory accesses" "" "0.99"& 
#j5= analyze "Target_within_body" "" "0.99"&
#j6= analyze "Non instruction opcode" "" "0.99"& 
#wait ${j1}
#wait ${j2}
#wait ${j3}
#wait ${j4}
#wait ${j5}
#wait ${j6}
#
#j1= analyze "Strongly Connected Component Data" "" "0.99"& 
#j2= analyze "Cross Layer Invalidation" "" "0.99"& 
#j3= analyze "All Instruction invariants" "TrimLimitedClamped,FixpointGrammar" "0.99" &
#j4= analyze "All Instruction invariants" "TrimLimitedClamped,FixpointGrammar" "0.98" &
#j5= analyze "All Instruction invariants" "TrimLimitedClamped,FixpointGrammar" "0.97" &
#j6= analyze "All Instruction invariants" "TrimLimitedClamped,FixpointGrammar" "0.90" &
##j5= analyze "Grammar convergent" "" &
#wait ${j1}
#wait ${j2}
#wait ${j3}
#wait ${j4}
#wait ${j5}
#wait ${j6}
#j1= analyze "All Instruction invariants" "TrimLimitedClamped,FixpointGrammar" "0.80" &
#j2= analyze "All Instruction invariants" "TrimLimitedClamped,FixpointGrammar" "0.70" &
#j3= analyze "All Instruction invariants" "TrimLimitedClamped,FixpointGrammar" "0.50" &
#wait ${j1}
#wait ${j2}
#wait ${j3}

analyze "All Instruction invariants" "TrimLimitedClamped,FixpointGrammar" "0.99" 
