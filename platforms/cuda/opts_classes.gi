Class(PatternMatcher, AttrMixin, rec(
    MAX_KERNEL := 25,
    MAX_PRIME := 17,
    MIN_SIZE := 32,
    MAX_SIZE := 680,
    filter := (self, e) -> When(e[1] * e[2] <= self.MAX_KERNEL ^ 2, e[1] <= self.MAX_KERNEL and e[2] <= self.MAX_KERNEL, e[1] <= self.MAX_KERNEL and e[2] >= self.MAX_KERNEL),
    size1 := (self) >> Filtered([self.MIN_SIZE..self.MAX_SIZE], i -> ForAny(DivisorPairs(i), self.filter) and ForAll(Factors(i), j -> not IsPrime(j) or j <= self.MAX_PRIME)),

    __call__ := meth(self, patterns)
        return WithBases(self, rec(patterns := patterns, operations := PrintOps));
    end,

    print := (self) >> Print(self.name, "(", self.conf, ", ", self.t, ")")
));

Class(constructor,AttrMixin, rec(

));

Class(merger,AttrMixin, rec(

));