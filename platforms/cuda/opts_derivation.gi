Import(simt);
Declare(PatternMatcher);

ParseOptsCUDA := function(conf, t)
    local p;
    p := PatternMatcher(conf, t);
    return p.apply();
end;

Class(PatternMatcher, AttrMixin, rec(
    MAX_KERNEL := 25,
    MAX_PRIME := 17,
    MIN_SIZE := 32,
    MAX_SIZE := 680,
    _thold := (self) >> self.MAX_KERNEL,
    size1 := (self) >> Filtered([self.MIN_SIZE..self.MAX_SIZE], i -> ForAny(DivisorPairs(i), e -> When(e[1] * e[2] <= self.MAX_KERNEL ^ 2, e[1] <= self.MAX_KERNEL and e[2] <= self.MAX_KERNEL, e[1] <= self.MAX_KERNEL and e[2] >= self.MAX_KERNEL))
                         and ForAll(Factors(i), j -> not IsPrime(j) or j <= self.MAX_PRIME)),
    _HPCSupportedSizesCUDA := (self) >> self.size1(),

    __call__ := meth(self, conf, t)
        return WithBases(self, rec(conf := conf, t := t, operations := PrintOps));
    end,

    print := (self) >> Print(self.name, "(", self.conf, ", ", self.t, ")"),

    #TODO: ORDER of Rules is important HOCKNEY130 -> HOCKNEY GENERAL -> CONV
    patterns := (self) >> [self.batch_dft_prdft, self.3d_dft_batchdft, self.3d_dft_idft_nonconv, 
                           self.tfcall_hockney_130, self.tfcall_hockney_general, self.tfcall_conv,
                           self.warpx, self.default_case],

    apply := meth(self) 
        local list, _opts, bool, itr;
        list := self.patterns();
        _opts := false;
        bool := false;
        itr := 1;
        if IsBound(self.conf.useCUDADevice) then 
            while bool = false do
                [bool, _opts] := ApplyFunc(list[itr], [self, self.conf, self.t]);
                itr := itr + 1;
            od;
        fi;
        if IsBound(self.conf.useCUDA) and bool = false then 
            return FFTXGlobals.getOpts(self.conf); 
        fi;
        if _opts <> false then
            Print("Found the opts in my NEW parse opts\n");
            return _opts;
        else   
            Error("Don't know how to derive opts!\n");
            return _opts;
        fi;
    end,       


#     conf_opts_batch := [let(_conf := FFTXGlobals.confBatchFFTCUDADevice(), _opts := FFTXGlobals.getOpts(_conf), _opts)];

#     conf_opts_batch_dft_prdft := [let(_conf := FFTXGlobals.confBatchFFTCUDADevice(), _opts := FFTXGlobals.getOpts(_conf), _opts.breakdownRules.TTwiddle := [ TTwiddle_Tw1 ],
#                 _opts.tags := [ASIMTKernelFlag(ASIMTGridDimX), ASIMTBlockDimY, ASIMTBlockDimX],
#                 _opts.globalUnrolling := 2*self._thold() + 1,
#                 _opts.breakdownRules.TTensorI := [CopyFields(IxA_L_split, rec(switch := true)), 
#                     fftx.platforms.cuda.L_IxA_SIMT, fftx.platforms.cuda.IxA_L_SIMT]::_opts.breakdownRules.TTensorI,
#                 _opts.breakdownRules.DFT := [CopyFields(DFT_tSPL_CT, rec(switch := true, 
#                     filter := e-> When(e[1]*e[2] <= self._thold()^2, e[1] <= self._thold() and e[2] <= self._thold(), e[1] <= self._thold() and e[2] >= self._thold())))]::_opts.breakdownRules.DFT),
#                     _opts.unparser.simt_synccluster := _opts.unparser.simt_syncblock,
#                 _opts.postProcessSums := (s, opts) -> let(s1 := ApplyStrategy(s, [ MergedRuleSet(RulesFuncSimp, RulesSums, RulesSIMTFission) ], BUA, opts),
#                     When(Collect(t, PRDFT)::Collect(t, IPRDFT) = [], 
#                         FixUpCUDASigmaSPL(FixUpCUDASigmaSPL_3Stage(s1, opts), opts),
#                         FixUpCUDASigmaSPL_3Stage_Real(s1, opts))), 
#                 _opts.postProcessCode := (c, opts) -> FixUpTeslaV_Code(c, opts),    
# #                _opts.postProcessCode := (c, opts) -> FixUpTeslaV_Code(PingPong_3Stages(c, opts), opts);    
#                 _opts.fixUpTeslaV_Code := true,
#                 _opts.operations.Print := s -> Print("<FFTX CUDA HPC Batch DFT options record>"), _opts];
    
#     conf_opts_3d_batch := [let( _conf := FFTXGlobals.confFFTCUDADevice(),_opts := FFTXGlobals.getOpts(_conf), _opts)];

#     conf_opts_3d_batch_ := [let(_conf := FFTXGlobals.confFFTCUDADevice(),_opts := FFTXGlobals.getOpts(_conf), 
#                             )];

    ttensorI_check := (t) -> ((Length(Collect(t, TTensorInd)) >= 1) or let(lst := Collect(t, TTensorI), (Length(lst) >= 1) and ForAll(lst, l->l.params[2] > 1))),
    dft_prdft_iprdft := (t) -> ((Length(Collect(t, DFT)) = 1) or (Length(Collect(t, PRDFT)) = 1) or (Length(Collect(t, IPRDFT)) = 1)),
    dft_prdft_iprdft_check_sizes := (t) -> ForAll(Flat(List(Collect(t, @(1, [DFT, PRDFT, IPRDFT])), j-> j.params[1])), i -> i in self._HPCSupportedSizesCUDA()),

    batch_dft_prdft_cond := meth(self, conf, t) 
        if ttensorI_check(t) and dft_prdft_iprdft(t) then
            return true;
        else
            return false;
        fi;
    end,

    # batch_dft_prdft_cond := meth(self, conf, t) 
    #     if ((Length(Collect(t, TTensorInd)) >= 1) or let(lst := Collect(t, TTensorI), (Length(lst) >= 1) and ForAll(lst, l->l.params[2] > 1))) and 
    #         ((Length(Collect(t, DFT)) = 1) or (Length(Collect(t, PRDFT)) = 1) or (Length(Collect(t, IPRDFT)) = 1)) then
    #         return true;
    #     else
    #         return false;
    #     fi;
    # end,

    
    batch_dft_prdft_cuda_cond := meth(self, conf, t)
        if ((Length(Collect(t, TTensorInd)) >= 1) or let(lst := Collect(t, TTensorI), (Length(lst) >= 1) and ForAll(lst, l->l.params[2] > 1))) and 
            ((Length(Collect(t, DFT)) = 1) or (Length(Collect(t, PRDFT)) = 1) or (Length(Collect(t, IPRDFT)) = 1)) then 
            if ForAll(Flat(List(Collect(t, @(1, [DFT, PRDFT, IPRDFT])), j-> j.params[1])), i -> i in self._HPCSupportedSizesCUDA())  then
                return true;
            else
                return false;
            fi;
        else
            return false;
        fi;
    end,
    
    3d_dft_batchdft_cond := meth(self, conf, t)
        local _tt, _conf, _opts;
        _tt := Collect(t, MDDFT)::Collect(t, MDPRDFT)::Collect(t, IMDPRDFT)::Collect(t, PrunedMDPRDFT)::Collect(t, PrunedIMDPRDFT);
        if Length(_tt) = 1 and Length(_tt[1].params[1]) = 3 then
            return true;
        else 
            return false;
        fi; 
    end,

    3d_dft_batchdft_cuda_cond := meth(self, conf, t)
        local _tt, _conf, _opts;
        _tt := Collect(t, MDDFT)::Collect(t, MDPRDFT)::Collect(t, IMDPRDFT)::Collect(t, PrunedMDPRDFT)::Collect(t, PrunedIMDPRDFT);
        if Length(_tt) = 1 and Length(_tt[1].params[1]) = 3 then
            if ForAll(_tt[1].params[1], i-> i in self._HPCSupportedSizesCUDA()) then
                return true;
            else
                return false;
            fi;
            return false;
        fi;
    end,
#     # detect batch of DFT/PRDFT
#     batch_dft_prdft := meth(self, conf, t) 
#     local _conf, _opts;
#     # detect batch of DFT/PRDFT
#         if ((Length(Collect(t, TTensorInd)) >= 1) or let(lst := Collect(t, TTensorI), (Length(lst) >= 1) and ForAll(lst, l->l.params[2] > 1))) and 
#             ((Length(Collect(t, DFT)) = 1) or (Length(Collect(t, PRDFT)) = 1) or (Length(Collect(t, IPRDFT)) = 1)) then
#             _conf := FFTXGlobals.confBatchFFTCUDADevice();
#             _opts := FFTXGlobals.getOpts(_conf);

#             # opts for high performance CUDA cuFFT
#             if ForAll(Flat(List(Collect(t, @(1, [DFT, PRDFT, IPRDFT])), j-> j.params[1])), i -> i in self._HPCSupportedSizesCUDA())  then
#                 _opts.breakdownRules.TTwiddle := [ TTwiddle_Tw1 ];
#                 _opts.tags := [ASIMTKernelFlag(ASIMTGridDimX), ASIMTBlockDimY, ASIMTBlockDimX];
                
#                 _opts.globalUnrolling := 2*self._thold() + 1;

#                 _opts.breakdownRules.TTensorI := [CopyFields(IxA_L_split, rec(switch := true)), 
#                     fftx.platforms.cuda.L_IxA_SIMT, fftx.platforms.cuda.IxA_L_SIMT]::_opts.breakdownRules.TTensorI;
#                 _opts.breakdownRules.DFT := [CopyFields(DFT_tSPL_CT, rec(switch := true, 
#                     filter := e-> When(e[1]*e[2] <= self._thold()^2, e[1] <= self._thold() and e[2] <= self._thold(), e[1] <= self._thold() and e[2] >= self._thold())))]::_opts.breakdownRules.DFT;
                
#                 _opts.unparser.simt_synccluster := _opts.unparser.simt_syncblock;
#                 _opts.postProcessSums := (s, opts) -> let(s1 := ApplyStrategy(s, [ MergedRuleSet(RulesFuncSimp, RulesSums, RulesSIMTFission) ], BUA, opts),
#                     When(Collect(t, PRDFT)::Collect(t, IPRDFT) = [], 
#                         FixUpCUDASigmaSPL(FixUpCUDASigmaSPL_3Stage(s1, opts), opts),
#                         FixUpCUDASigmaSPL_3Stage_Real(s1, opts))); 
#                 _opts.postProcessCode := (c, opts) -> FixUpTeslaV_Code(c, opts);    
# #                _opts.postProcessCode := (c, opts) -> FixUpTeslaV_Code(PingPong_3Stages(c, opts), opts);    
#                 _opts.fixUpTeslaV_Code := true;

#                 _opts.operations.Print := s -> Print("<FFTX CUDA HPC Batch DFT options record>");

#             fi;
#             return [true, _opts];
#         fi;
#         return [false, false];
#     end,

    #3D DFT/Batch DFT
    3d_dft_batchdft := meth(self, conf, t)
    local _tt, _conf, _opts;
    _tt := Collect(t, MDDFT)::Collect(t, MDPRDFT)::Collect(t, IMDPRDFT)::Collect(t, PrunedMDPRDFT)::Collect(t, PrunedIMDPRDFT);
        if Length(_tt) = 1 and Length(_tt[1].params[1]) = 3 then
            _conf := FFTXGlobals.confFFTCUDADevice();
            _opts := FFTXGlobals.getOpts(_conf);
#                Error();

            # opts for high performance CUDA cuFFT
            if ForAll(_tt[1].params[1], i-> i in self._HPCSupportedSizesCUDA()) then
                _opts.breakdownRules.MDDFT := [fftx.platforms.cuda.MDDFT_tSPL_Pease_SIMT];
                _opts.breakdownRules.MDPRDFT := [fftx.platforms.cuda.MDPRDFT_tSPL_Pease_SIMT];
                _opts.breakdownRules.IMDPRDFT := [fftx.platforms.cuda.IMDPRDFT_tSPL_Pease_SIMT];
                _opts.breakdownRules.TTwiddle := [ TTwiddle_Tw1 ];
                _opts.breakdownRules.PrunedMDPRDFT := [ PrunedMDPRDFT_tSPL_Pease_SIMT ];
                _opts.breakdownRules.PrunedIMDPRDFT := [ PrunedIMDPRDFT_tSPL_Pease_SIMT ];
                _opts.breakdownRules.PrunedDFT := [ PrunedDFT_base, PrunedDFT_DFT, PrunedDFT_CT, PrunedDFT_CT_rec_block, 
                    CopyFields(PrunedDFT_tSPL_CT, rec(switch := true)) ];
                
                _opts.globalUnrolling := 2*self._thold() + 1;
                #Error();
                _opts.breakdownRules.TTensorI := [CopyFields(IxA_L_split, rec(switch := true)), 
                    fftx.platforms.cuda.L_IxA_SIMT, fftx.platforms.cuda.IxA_L_SIMT]:: 
                    When(ForAny(_tt, _t -> ObjId(_t) in [PrunedMDPRDFT, PrunedIMDPRDFT]), 
                        [fftx.platforms.cuda.IxA_SIMT_peelof, fftx.platforms.cuda.IxA_SIMT_peelof2], [])::_opts.breakdownRules.TTensorI;
                _opts.breakdownRules.DFT := [CopyFields(DFT_tSPL_CT, rec(switch := true, 
                    filter := e-> When(e[1]*e[2] <= self._thold()^2, e[1] <= self._thold() and e[2] <= self._thold(), e[1] <= self._thold() and e[2] >= self._thold())))]::_opts.breakdownRules.DFT;
                
                _opts.unparser.simt_synccluster := _opts.unparser.simt_syncblock;
#                _opts.postProcessSums := (s, opts) -> let(s1 := ApplyStrategy(s, [ MergedRuleSet(RulesFuncSimp, RulesSums, RulesSIMTFission) ], BUA, opts),
#                    FixUpCUDASigmaSPL_3Stage(s1, opts)); 
                _opts.postProcessSums := (s, opts) -> let(s1 := ApplyStrategy(s, [ MergedRuleSet(RulesFuncSimp, RulesSums, RulesSIMTFission) ], BUA, opts),
                    When(Collect(t, MDPRDFT)::Collect(t, IMDPRDFT) = [], 
                        FixUpCUDASigmaSPL_3Stage(s1, opts),
                        FixUpCUDASigmaSPL_3Stage_Real(s1, opts))); 


                _opts.postProcessCode := (c, opts) -> FixUpTeslaV_Code(c, opts);    
#                _opts.postProcessCode := (c, opts) -> FixUpTeslaV_Code(PingPong_3Stages(c, opts), opts);    
                _opts.fixUpTeslaV_Code := true;

                if ((Length(Collect(t, TTensorInd)) >= 1) or let(lst := Collect(t, TTensorI), (Length(lst) >= 1) and ForAll(lst, l->l.params[2] > 1))) then
                    _opts.operations.Print := s -> Print("<FFTX CUDA HPC Batch MDDFT/MDPRDFT/MDIPRDFT options record>");
                    _opts.tags := [ASIMTKernelFlag(ASIMTGridDimX), ASIMTGridDimY, ASIMTBlockDimY, ASIMTBlockDimX];
                else
                    _opts.operations.Print := s -> Print("<FFTX CUDA HPC MDDFT/MDPRDFT/MDIPRDFT options record>");
                    _opts.tags := [ASIMTKernelFlag(ASIMTGridDimX), ASIMTBlockDimY, ASIMTBlockDimX];
                fi;

                _opts.HPCSupportedSizesCUDA := self._HPCSupportedSizesCUDA();

            fi;
            return [true, _opts];
        fi;
        return [false, false];
    end,

    #detect 3D DFT/iDFT but non-convolution case
    3d_dft_idft_nonconv := meth(self, conf, t)
    local _tt, _conf, _opts;
    _tt := Collect(t, MDDFT);
        if Length(_tt) = 2 and ForAll(_tt, i->Length(i.params[1]) = 3) and Sum(List(_tt, i->i.params[2])) = Product(_tt[1].params[1]) then
            _conf := FFTXGlobals.confFFTCUDADevice();
            _opts := FFTXGlobals.getOpts(_conf);

            # opts for high performance CUDA cuFFT
            if Length(Filtered(_tt, i -> ObjId(i) = MDDFT)) > 0 and ForAll(_tt[1].params[1], i-> i in self._HPCSupportedSizesCUDA()) then
                _opts.breakdownRules.MDDFT := [fftx.platforms.cuda.MDDFT_tSPL_Pease_SIMT];
                _opts.breakdownRules.MDPRDFT := [fftx.platforms.cuda.MDPRDFT_tSPL_Pease_SIMT];
                _opts.breakdownRules.IMDPRDFT := [fftx.platforms.cuda.IMDPRDFT_tSPL_Pease_SIMT];
                _opts.breakdownRules.TTwiddle := [ TTwiddle_Tw1 ];
                _opts.tags := [ASIMTKernelFlag(ASIMTGridDimX), ASIMTBlockDimY, ASIMTBlockDimX];
                
                _opts.globalUnrolling := 2*self._thold() + 1;

                _opts.breakdownRules.TTensorI := [CopyFields(IxA_L_split, rec(switch := true)), 
                    fftx.platforms.cuda.L_IxA_SIMT, fftx.platforms.cuda.IxA_L_SIMT]::_opts.breakdownRules.TTensorI;
                _opts.breakdownRules.DFT := [CopyFields(DFT_tSPL_CT, rec(switch := true, 
                    filter := e-> When(e[1]*e[2] <= self._thold()^2, e[1] <= self._thold() and e[2] <= self._thold(), e[1] <= self._thold() and e[2] >= self._thold())))]::_opts.breakdownRules.DFT;
                
                _opts.unparser.simt_synccluster := _opts.unparser.simt_syncblock;
                _opts.postProcessSums := (s, opts) -> let(s1 := ApplyStrategy(s, [ MergedRuleSet(RulesFuncSimp, RulesSums, RulesSIMTFission) ], BUA, opts),
                    FixUpCUDASigmaSPL_3Stage(s1, opts)); 
                _opts.postProcessCode := (c, opts) -> FixUpTeslaV_Code(PingPong_3Stages(c, opts), opts);    
                _opts.fixUpTeslaV_Code := true;

                _opts.operations.Print := s -> Print("<FFTX CUDA HPC MDDFT options record>");

            fi;
            return [true, _opts];
        fi;
        return [false, false];
    end,

    # #TFCall convolution
    tfcall_conv := meth(self, conf, t)
    local tt, _tt, _conf, _opts; 
    tt := _promote1(Copy(t));
    if ObjId(tt) = TFCall then
        _tt := tt.params[1];
        # check for convolution
        if (ObjId(_tt) in [PrunedMDPRDFT, PrunedIMDPRDFT, MDRConv, MDRConvR, IOPrunedMDRConv]) or ((ObjId(_tt) in [TTensorI, TTensorInd]) and (ObjId(_tt.params[1]) in [MDRConv, MDRConvR])) then 
            _conf := FFTXGlobals.confMDRConvCUDADevice();
            _opts := FFTXGlobals.getOpts(_conf);

            # opts for high performance CUDA cuFFT
            if (ObjId(_tt) in [MDRConv, MDRConvR, IOPrunedMDRConv] and ForAll(_tt.params[1], i-> i in self._HPCSupportedSizesCUDA())) or
                (ObjId(_tt) in [TTensorI, TTensorInd] and ForAll(_tt.params[1].params[1], i-> i in self._HPCSupportedSizesCUDA())) then
                _opts.breakdownRules.MDDFT := [fftx.platforms.cuda.MDDFT_tSPL_Pease_SIMT];
                _opts.breakdownRules.MDPRDFT := [fftx.platforms.cuda.MDPRDFT_tSPL_Pease_SIMT];
                _opts.breakdownRules.IMDPRDFT := [fftx.platforms.cuda.IMDPRDFT_tSPL_Pease_SIMT];
                _opts.breakdownRules.TTwiddle := [ TTwiddle_Tw1 ];
                
                # handle IOPrunedMDRConv in CUDA -- TBD
                _opts.breakdownRules.PrunedMDPRDFT := [ PrunedMDPRDFT_tSPL_Pease_SIMT ];
                _opts.breakdownRules.PrunedIMDPRDFT := [ PrunedIMDPRDFT_tSPL_Pease_SIMT ];
#                    _opts.breakdownRules.PrunedMDPRDFT := [PrunedMDPRDFT_tSPL_Base, PrunedMDPRDFT_tSPL_RowCol1];
#                    _opts.breakdownRules.PrunedIMDPRDFT := [PrunedIMDPRDFT_tSPL_Base, PrunedIMDPRDFT_tSPL_RowCol1];
                _opts.breakdownRules.PrunedMDDFT := [PrunedMDDFT_tSPL_Base, PrunedMDDFT_tSPL_RowCol];
                _opts.breakdownRules.PrunedIMDDFT := [PrunedIMDDFT_tSPL_Base, PrunedIMDDFT_tSPL_RowCol];
#                    _opts.breakdownRules.IOPrunedMDRConv := [IOPrunedMDRConv_tSPL_InvDiagFwd];
                _opts.breakdownRules.IOPrunedMDRConv := [IOPrunedMDRConv_tSPL_5stage];
                
                _opts.breakdownRules.TTensorInd := [TTensorInd_SIMT_peelof, TTensorInd_SIMT_peelof2, TTensorInd_SIMT];
                
                _opts.globalUnrolling := 2*self._thold() + 1;

                _opts.breakdownRules.TTensorI := [CopyFields(IxA_L_split, rec(switch := true)),
                    fftx.platforms.cuda.L_IxA_SIMT, fftx.platforms.cuda.IxA_L_SIMT]::
                    When(ObjId(_tt) in [PrunedMDPRDFT, PrunedIMDPRDFT, IOPrunedMDRConv], 
                            [fftx.platforms.cuda.IxA_SIMT_peelof, fftx.platforms.cuda.IxA_SIMT_peelof2], [])::_opts.breakdownRules.TTensorI;
                    
                _opts.breakdownRules.DFT := [CopyFields(DFT_tSPL_CT, rec(switch := true, 
                    filter := e-> When(e[1]*e[2] <= self._thold()^2, e[1] <= self._thold() and e[2] <= self._thold(), e[1] <= self._thold() and e[2] >= self._thold())))]::_opts.breakdownRules.DFT;
                
                _opts.unparser.simt_synccluster := _opts.unparser.simt_syncblock;
#                _opts.postProcessSums := (s, opts) -> let(s1 := ApplyStrategy(s, [ MergedRuleSet(RulesFuncSimp, RulesSums, RulesSIMTFission) ], BUA, opts),
#                    FixUpCUDASigmaSPL_3Stage(s1, opts)); 
                _opts.postProcessSums := (s, opts) -> let(s1 := ApplyStrategy(s, [ MergedRuleSet(RulesDiagStandalonePointwise, 
                        RulesFuncSimp, RulesSums, RulesSIMTFission) ], BUA, opts),
                    When(Collect(t, MDPRDFT)::Collect(t, IMDPRDFT) = [], 
                        FixUpCUDASigmaSPL_3Stage(s1, opts),
                        FixUpCUDASigmaSPL_3Stage_Real(s1, opts))); 


                _opts.postProcessCode := (c, opts) -> FixUpTeslaV_Code(c, opts);    
#                _opts.postProcessCode := (c, opts) -> FixUpTeslaV_Code(PingPong_3Stages(c, opts), opts);    
                _opts.fixUpTeslaV_Code := true;

                if ((Length(Collect(t, TTensorInd)) >= 1) or let(lst := Collect(t, TTensorI), (Length(lst) >= 1) and ForAll(lst, l->l.params[2] > 1))) then
                    _opts.operations.Print := s -> Print("<FFTX CUDA HPC Batch MDRConv/MDRConvR/IOPrunedMDRConv options record>");
                    _opts.tags := [ASIMTKernelFlag(ASIMTGridDimX), ASIMTGridDimY, ASIMTBlockDimY, ASIMTBlockDimX];
                else
                    _opts.operations.Print := s -> Print("<FFTX CUDA HPC MDRConv/MDRConvR/IOPrunedMDRConv options record>");
                    _opts.tags := [ASIMTKernelFlag(ASIMTGridDimX), ASIMTBlockDimY, ASIMTBlockDimX];
                fi;

                _opts.HPCSupportedSizesCUDA := self._HPCSupportedSizesCUDA();

            fi;
            return [true, _opts];
        fi;
    fi;
    return [false, false];
    end,

    #TFCall hockney 130 case
    tfcall_hockney_130 := meth(self,conf, t) 
    local tt, _tt, _conf, _opts;
    tt := _promote1(Copy(t));
    if ObjId(tt) = TFCall then
        _tt := tt.params[1];
        if ObjId(_tt) = IOPrunedMDRConv  and _tt.params[1] = [130,130,130] then
            _conf := FFTXGlobals.confHockneyMlcCUDADevice();
            _opts := FFTXGlobals.getOpts(_conf);
            return [true, _opts];
        fi;
    fi;
    return [false, false];
    end,

    #TFCall hockney general case
    tfcall_hockney_general := meth(self,conf,t) 
    local tt, _tt, _conf, _opts;
    tt := _promote1(Copy(t));
    if ObjId(tt) = TFCall then
        _tt := tt.params[1];
         if ObjId(_tt) = IOPrunedMDRConv then
            _conf := FFTXGlobals.confMDRConvCUDADevice();
            _opts := FFTXGlobals.getOpts(_conf);
            _opts.tags := [ASIMTKernelFlag(ASIMTGridDimY), ASIMTGridDimX, ASIMTBlockDimZ];
             return [true, _opts];
        fi;
    fi;
    return [false, false];
    end,

    #WarpX
    warpx := meth(self, conf, t)
    local tt, _tt, _conf, _opts; 
    tt := _promote1(Copy(t));
    # check for WarpX
    _conf := FFTXGlobals.confWarpXCUDADevice();
    _opts := FFTXGlobals.getOpts(_conf);
    tt := _opts.preProcess(Copy(t));
    if ObjId(tt) = TFCall and ObjId(tt.params[1]) = TCompose then
        _tt := tt.params[1].params[1];
        # detect promoted WarpX
        if IsList(_tt) and Length(_tt) = 3 and List(_tt, ObjId) = [ TNoDiagPullinRight, TRC, TNoDiagPullinLeft ] then
            return [true, _opts];
        fi;
    fi;
    return [false, false];
    end,

    default_case := meth(self, conf, t) 
        return [true, FFTXGlobals.getOpts(conf)]; 
    end
));