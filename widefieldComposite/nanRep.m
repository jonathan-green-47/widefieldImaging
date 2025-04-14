function A = nanRep(A, fill)
% A = nanRep(A, fill) replaces all NaNs in A with FILL. FILL can be empty,
% but A will be converted to a linear array if FILL is empty.

if isempty(fill)
    A(isnan(A)) = [];
else
    A(isnan(A)) = fill;
end