
##  Copyright (c) 2018-2023, Carnegie Mellon University
##  See LICENSE for details

# multidimensional batch of 1D complex DFTs

Load(fftx);
ImportAll(fftx);


b1 := 2;
b2 := 2;
N := 64;

t := let(
    name := "grid_dft"::StringInt(N)::"_"::StringInt(b1)::"x"::StringInt(b2),
    TFCall(TRC(TTensorI(DFT(N, -1), b1*b2 ,APar, APar)), rec(fname := name, params := []))
);

conf := LocalConfig.fftx.confGPU();
opts := conf.getOpts(t);
tt := opts.tagIt(t);

c := opts.fftxGen(tt);
opts.prettyPrint(c);
