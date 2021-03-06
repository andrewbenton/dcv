﻿/**
Module implements various algorithms used often in computer vision.

$(DL Module contains:
    $(DD 
            $(LINK2 #norm,norm)
            $(LINK2 #normalized,normalized)
            $(LINK2 #scaled,scaled)
            $(LINK2 #ranged,ranged)
    )
)

Copyright: Copyright Relja Ljubobratovic 2016.

Authors: Relja Ljubobratovic

License: $(LINK3 http://www.boost.org/LICENSE_1_0.txt, Boost Software License - Version 1.0).
*/

module dcv.core.algorithm;

import std.range;
import std.traits : isNumeric, isFloatingPoint;

import mir.ndslice.slice : Slice, sliced, DeepElementType;
import mir.ndslice.algorithm : ndReduce, ndEach, Yes;

version(LDC)
{
    import ldc.intrinsics : sqrt = llvm_sqrt, fabs = llvm_fabs, min = llvm_minnum, max = llvm_maxnum;
}
else
{
    import std.math : sqrt, fabs;
    import std.algorithm.comparison : min, max;
}

version(unittest)
{
    import std.math : approxEqual;
}

/**
Type of matrix and vector norms.
*/
enum NormType
{
    INF, /// Infinite norm, max(x)
    L1, /// 1-norm, sum(abs(x))
    L2 /// Eucledian norm, sqrt(sum(x^^2))
}

/**
Calculate value of various norm types for vectors and matrices.

Params:
    tensor = Tensor of which the norm value is calculated.
    normType = requested type of norm.

Returns:
    Calculated norm value.
*/
@nogc pure nothrow auto norm(Range, size_t N)(auto ref Slice!(N, Range) tensor, NormType normType)
{
    alias T = DeepElementType!(typeof(tensor));

    static if (isFloatingPoint!T)
        auto min = T.min_normal;
    else
        auto min = T.min;

    final switch (normType)
    {
    case NormType.INF:
        return min.ndReduce!(max, Yes.vectorized)(tensor);
    case NormType.L1:
        return T(0).ndReduce!((a, b) => fabs(a + b), Yes.vectorized)(tensor);
    case NormType.L2:
        return T(0).ndReduce!((a, b) => a + (b * b), Yes.vectorized)(tensor).sqrt;
    }
}

// Test INF norm
pure nothrow unittest
{
    import std.conv : to;

    auto t1 = tensor1();
    auto t2 = tensor2();
    auto t3 = tensor3();

    assert(approxEqual(t1.norm(NormType.INF), 3.0f));
    assert(approxEqual(t2.norm(NormType.INF), 9.0f));
    assert(approxEqual(t3.norm(NormType.INF), 27.0f));
}

// Test L1 norm - test vector sum == 1 after normalization
pure nothrow unittest
{
    auto t1 = tensor1();
    auto t2 = tensor2();
    auto t3 = tensor3();

    t1[] /= t1.norm(NormType.L1);
    t2[] /= t2.norm(NormType.L1);
    t3[] /= t3.norm(NormType.L1);

    assert(approxEqual(ndReduce!"a+b"(0.0f, t1), 1.0f));
    assert(approxEqual(ndReduce!"a+b"(0.0f, t2), 1.0f));
    assert(approxEqual(ndReduce!"a+b"(0.0f, t3), 1.0f));
}

// Test L2 norm - test vector length == 1 after normalization
pure nothrow unittest
{
    auto t1 = tensor1();
    auto t2 = tensor2();
    auto t3 = tensor3();

    t1[] /= t1.norm(NormType.L2);
    t2[] /= t2.norm(NormType.L2);
    t3[] /= t3.norm(NormType.L2);

    assert(approxEqual(ndReduce!( (v, n) => v + n*n)(0.0f, t1), 1.0f));
    assert(approxEqual(ndReduce!( (v, n) => v + n*n)(0.0f, t2), 1.0f));
    assert(approxEqual(ndReduce!( (v, n) => v + n*n)(0.0f, t3), 1.0f));
}

/**
Normalize tensor values using given norm type.

Params:
    tensor = Tensor which is normalized.
    normType = Requested norm type for normalization.

Returns:
    Returns normalized input tensor.
*/
@nogc nothrow auto normalized(Range, size_t N)(auto ref Slice!(N, Range) tensor, NormType normType = NormType.L2)
{
    alias T = DeepElementType!(typeof(tensor));
    auto n = tensor.norm(normType);
    static if (isFloatingPoint!T)
        tensor[] /= n;
    else
        tensor.ndEach!((ref v) { v = cast(T)(cast(real)v / n); }, Yes.vectorized);
    return tensor;
}

nothrow unittest
{
    auto t = tensor1();
    auto tn = normalized(t, NormType.L1);
    assert(t.ptr == tn.ptr);
}

/**
Scale tensor values.

Params:
    tensor = Input tensor.
    alpha = Multiplier value.
    beta = Offset value.

Performs value modification of tensor elements using following formula:
----
ref output = alpha * (input) + beta;
----

Returns:
    Scaled input tensor.
    
*/
@nogc nothrow auto scaled(Scalar, Range, size_t N)(auto ref Slice!(N, Range) tensor, Scalar alpha = 1, Scalar beta = 0)
        if (isNumeric!Scalar)
{
    tensor.ndEach!((ref v) { v = alpha * (v) + beta; }, Yes.vectorized);
    return tensor;
}

nothrow unittest
{
    auto t = tensor1();
    auto ts = t.scaled(10.0f, 2.0f);

    assert(t.ptr == ts.ptr);

    assert(approxEqual(ts[0], 12.0f));
    assert(approxEqual(ts[1], 22.0f));
    assert(approxEqual(ts[2], 32.0f));
}

/**
In-place tensor scaling to fit given value range.

Params:
    tensor = Input tensor.
    minValue = Minimal value output tensor should contain.
    maxValue = Maximal value output tensor should contain.

*/
@nogc auto ranged(Scalar, Range, size_t N)(auto ref Slice!(N, Range) tensor,
        Scalar minValue = 0, Scalar maxValue = 1) if (isNumeric!Scalar)
{
    alias RangeElementType = DeepElementType!(typeof(tensor));

    auto _min = ndReduce!(min, Yes.vectorized)(RangeElementType.max, tensor);
    static if (isFloatingPoint!RangeElementType)
        auto _max = ndReduce!(max, Yes.vectorized)(RangeElementType.min_normal, tensor);
    else
        auto _max = ndReduce!(max, Yes.vectorized)(RangeElementType.min, tensor);

    auto rn_val = _max - _min;
    auto sc_val = maxValue - minValue;

    tensor.ndEach!((ref a) { a = sc_val * ((a - _min) / rn_val) + minValue; }, Yes.vectorized);

    return tensor;
}

unittest
{
    immutable smin = -10.0f;
    immutable smax = 15.0f;

    auto t1 = tensor1();
    auto t2 = tensor2();
    auto t3 = tensor3();

    auto t1r = t1.ranged(smin, smax);
    auto t2r = t2.ranged(smin, smax);
    auto t3r = t3.ranged(smin, smax);

    assert(t1.ptr == t1r.ptr);
    assert(t2.ptr == t2r.ptr);
    assert(t3.ptr == t3r.ptr);

}

nothrow unittest
{
    immutable smin = -10.0f;
    immutable smax = 15.0f;

    auto t1 = tensor1();
    auto t2 = tensor2();
    auto t3 = tensor3();

    auto t1r = t1.ranged(smin, smax);
    auto t2r = t2.ranged(smin, smax);
    auto t3r = t3.ranged(smin, smax);

    assert(approxEqual(ndReduce!min(float.max, t1r), smin));
    assert(approxEqual(ndReduce!max(float.min_normal, t1r), smax));

    assert(approxEqual(ndReduce!min(float.max, t2r), smin));
    assert(approxEqual(ndReduce!max(float.min_normal, t2r), smax));

    assert(approxEqual(ndReduce!min(float.max, t3r), smin));
    assert(approxEqual(ndReduce!max(float.min_normal, t3r), smax));
}

version (unittest)
{
    auto tensor1()
    {
        return [1.0f, 2.0f, 3.0f].sliced(3);
    }

    auto tensor2()
    {
        return [1.0f, 2.0f, 3.0f, 4.0f, 5.0f, 6.0f, 7.0f, 8.0f, 9.0f].sliced(3, 3);
    }

    auto tensor3()
    {
        return [1.0f, 2.0f, 3.0f,       4.0f, 5.0f, 6.0f,       7.0f, 8.0f, 9.0f, 
               10.0f, 11.0f, 12.0f,     13.0f, 14.0f, 15.0f,    16.0f, 17.0f, 18.0f, 
               19.0f, 20.0f, 21.0f,     22.0f, 23.0f, 24.0f,    25.0f, 26.0f, 27.0f].sliced(3, 3, 3);
    }
}
