{ *****************************************************************************
  This file is licensed to you under the Apache License, Version 2.0 (the
  "License"); you may not use this file except in compliance
  with the License. A copy of this licence is found in the root directory of
  this project in the file LICENCE.txt or alternatively at
  http://www.apache.org/licenses/LICENSE-2.0
  Unless required by applicable law or agreed to in writing,
  software distributed under the License is distributed on an
  "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
  KIND, either express or implied.  See the License for the
  specific language governing permissions and limitations
  under the License.
  ***************************************************************************** }
unit uScale;
(*****************************************************************)
(* High quality resampling of VCL-bitmaps using various filters  *)
(* and including fast threaded routines.                         *)
(* Copyright 2003-2023 Renate Schaaf                             *)
(* Inspired by A.Melander, M.Lischke, E.Grange.                  *)
(* Supported Delphi-versions: 10.x and up, probably works with   *)
(* some earlier versions, but untested.                          *)
(* Caution! The threaded routine itself is not threadsafe,       *)
(* it uses global variables for the threads.                     *)
(* The "beef" of the algorithm used is in the routines           *)
(*   MakeContributors and ProcessRow*                            *)
(*****************************************************************)



interface

uses WinApi.Windows, VCL.Graphics, System.Types, System.UITypes,
  System.Threading, System.SysUtils, System.Classes, System.Math,
  System.SyncObjs;

{$IFOPT O-}
{$DEFINE O_MINUS}
{$O+}
{$ENDIF}
{$IFOPT Q+}
{$DEFINE Q_PLUS}
{$Q-}
{$ENDIF}

type
  // filter types
  TFilter = (cfBox, cfBilinear, cfBicubic, cfMine, cfLanczos,
    cfBSpline);

  TFilterFunction = function(x: double): double;

  eParallelException = class(Exception); // waiting to be used

  TFloatRect = record
    Left, Top, Right, Bottom: double;
  end;

  TBGRAInt = record
    b, g, r, a: integer;
  end;

  PBGRAInt = ^TBGRAInt;

  TBGRAIntArray = array of TBGRAInt;

  TBGRInt = record
    b, g, r: integer;
  end;

  PBGRInt = ^TBGRInt;

  TBGRIntArray = array of TBGRInt;

  TIntArray = array of integer;

  TContributor = record
    Min, High: integer;
    // Min: start source pixel
    // High+1: number of source pixels to contribute to the result
    Weights: array of integer; // floats scaled by $100  or $400
  end;

  // amIndependent: all channels are resampled independently
  //
  // amPreMultiply: RBG-channels are pre-multiplied by alpha-channel before resampling,
  // after that the resampled alpha-channel is divided out again, unless=0. This means that pixels
  // with alpha=0 have no contribution to the result.
  //
  // amIgnore: Resampling ignores the alpha-channel and only stores RGB into target. Useful if the alpha-channel
  // is not needed or the target already contains a custom alpha-channel which should not be changed
  TAlphaCombineMode = (amIndependent, amPreMultiply, amIgnore);

  TContribArray = array of TContributor;

  TResamplingThread = class(TThread)
  private
    fResamplingThreadProc: TProc;
  protected
    procedure Execute; override;
  public
    Wakeup, Done, Ready: TEvent;
    procedure RunAnonProc(aProc: TProc);
    Constructor Create;
    Destructor Destroy; override;
  end;

const
  // can be made a tad smaller for performance
  DefaultRadius: array [TFilter] of single = (0.5, 1, 2, 2, 3, 2);

  //constants used to divide the work for threading
  _ChunkWidth: integer = 720;
  _ChunkHeight: integer = 8;
  MaxThreadCount: integer = 64;

var
  ResamplingThreads: array of TResamplingThread;

/// <summary> Resampling of complete bitmaps with various options. Uses the ZoomResample.. functions internally </summary>
/// <param name="NewWidth"> Width of target bitmap. Target will be resized. </param>
/// <param name="NewHeight"> Height of target bitmap. Target will be resized. </param>
/// <param name="Source"> Source bitmap, will be set to pf32bit </param>
/// <param name="Target"> Target bitmap, will be set to pf32bit </param>
/// <param name="Filter"> Defines the kernel function for resampling </param>
/// <param name="Radius"> Defines the range of pixels to contribute to the result. Value 0 takes the default radius for the filter. </param>
/// <param name="Parallel"> If true the resampling work is divided into parallel threads. </param>
/// <param name="AlphaCombineMode"> Options for combining the alpha-channel: amIndependent, amPreMultiply, amIgnore </param>
procedure Resample(NewWidth, NewHeight: integer; const Source, Target: TBitmap;
  Filter: TFilter; Radius: single; Parallel: boolean;
  AlphaCombineMode: TAlphaCombineMode);

/// <summary> Resamples a rectangle of the Source to the Target. </summary>
/// <param name="NewWidth"> Width of target bitmap. Target will be resized. </param>
/// <param name="NewHeight"> Height of target bitmap. Target will be resized. </param>
/// <param name="Source"> Source bitmap, will be set to pf32bit </param>
/// <param name="Target"> Target bitmap, will be set to pf32bit </param>
/// <param name="SourceRect"> Rectangle in the source which will be resampled, has floating point boundaries for smooth zooms. </param>
/// <param name="Filter"> Defines the kernel function for resampling </param>
/// <param name="Radius"> Defines the range of pixels to contribute to the result. Value 0 takes the default radius for the filter. </param>
/// <param name="AlphaCombineMode"> Options for the alpha-channel: amIndependent, amPreMultiply, amIgnore </param>
procedure ZoomResample(NewWidth, NewHeight: integer;
  const Source, Target: TBitmap; SourceRect: TFloatRect; Filter: TFilter;
  Radius: single; AlphaCombineMode: TAlphaCombineMode);

//!Caution: The following routine uses threads, but is itself not threadsafe, because the threads are
//!global variables. If you must use it in more than one thread, protect it by a critical section.

/// <summary> Resamples a rectangle of the Source to the Target using parallel threads. </summary>
/// <param name="NewWidth"> Width of target bitmap. Target will be resized. </param>
/// <param name="NewHeight"> Height of target bitmap. Target will be resized. </param>
/// <param name="Source"> Source bitmap, will be set to pf32bit </param>
/// <param name="Target"> Target bitmap, will be set to pf32bit </param>
/// <param name="SourceRect"> Rectangle in the source which will be resampled, has floating point boundaries for smooth zooms. </param>
/// <param name="Filter"> Defines the kernel function for resampling </param>
/// <param name="Radius"> Defines the range of pixels to contribute to the result. Value 0 takes the default radius for the filter. </param>
/// <param name="AlphaCombineMode"> Options for the alpha-channel: amIndependent, amPreMultiply, amIgnore </param>
procedure ZoomResampleParallelThreads(NewWidth, NewHeight: integer;
  const Source, Target: TBitmap; SourceRect: TFloatRect; Filter: TFilter;
  Radius: single; AlphaCombineMode: TAlphaCombineMode);

//The following procedure allows you to compare performance of normal threads to
//the built-in TTask-threading.
//Timings with TTask tend to be erratic. Sometimes it takes a very long time,
//I think this happens whenever the system deems it necessary to re-initialize
//the threading-framework.
/// <summary> Resamples a rectangle of the Source to the Target using parallel tasks (TTask). </summary>
/// <param name="NewWidth"> Width of target bitmap. Target will be resized. </param>
/// <param name="NewHeight"> Height of target bitmap. Target will be resized. </param>
/// <param name="Source"> Source bitmap, will be set to pf32bit </param>
/// <param name="Target"> Target bitmap, will be set to pf32bit </param>
/// <param name="SourceRect"> Rectangle in the source which will be resampled, has floating point boundaries for smooth zooms. </param>
/// <param name="Filter"> Defines the kernel function for resampling </param>
/// <param name="Radius"> Defines the range of pixels to contribute to the result. Value 0 takes the default radius for the filter. </param>
/// <param name="AlphaCombineMode"> Options for the alpha-channel: amIndependent, amPreMultiply, amIgnore </param>
procedure ZoomResampleParallelTasks(NewWidth, NewHeight: integer;
  const Source, Target: TBitmap; SourceRect: TFloatRect; Filter: TFilter;
  Radius: single; AlphaCombineMode: TAlphaCombineMode);

function FloatRect(Aleft, ATop, aRight, aBottom: double): TFloatRect;
  overload; inline;
function FloatRect(ARect: TRect): TFloatRect; overload; inline;

implementation

function FloatRect(Aleft, ATop, aRight, aBottom: double): TFloatRect;
begin
  with Result do
  begin
    Left := Aleft;
    Top := ATop;
    Right := aRight;
    Bottom := aBottom;
  end;
end;

function FloatRect(ARect: TRect): TFloatRect;
begin
  with Result do
  begin
    Left := ARect.Left;
    Top := ARect.Top;
    Right := ARect.Right;
    Bottom := ARect.Bottom;
  end;
end;

//follow the filter functions
function Box(x: double): double; inline;
begin
  x := abs(x);
  if x > 1 then
    Result := 0
  else
    Result := 0.5;
end;

function Linear(x: double): double; inline;
begin
  x := abs(x);
  if x < 1 then
    Result := 1 - x
  else
    Result := 0;
end;

function BSpline(x: double): double; inline;
begin
  x := abs(x);
  if x < 0.5 then
    Result := 8 * x * x * (x - 1) + 4 / 3
  else if x < 1 then
    Result := 8 / 3 * sqr(1 - x) * (1 - x)
  else
    Result := 0;
end;

const
  beta = 0.52;
  beta2 = beta * beta;
  alpha = 105 / (16 - 112 * beta2);
  aa = 1 / 7 * alpha;
  bb = -1 / 5 * alpha * (2 + beta2);
  cc = 1 / 3 * alpha * (1 + 2 * beta2);
  dd = -alpha * beta2;

function Mine(x: double): double; inline;
begin
  x := abs(x);
  if x > 1 then
    Result := 0
  else
    Result := 7 * aa * x * x * x * x * x * x + 5 * bb * x * x * x * x + 3 * cc *
      sqr(x) + dd;
end;

const
  ac = -2;

function Bicubic(x: double): double; inline;
begin
  x := abs(x);
  if x < 1 / 2 then
    Result := 4 * (ac + 8) * x * x * x - 2 * (ac + 12) * x * x + 2
  else if x < 1 then
    Result := 2 * ac * (2 * x * x * x - 5 * x * x + 4 * x - 1)
  else
    Result := 0;
end;

function Lanczos(x: double): double;
var
  y: double;
begin
  x := abs(x);
  y := Pi * x;
  if y = 0 then
    Result := 3
  else if x < 1 then
    Result := sin(3 * y) * sin(y) / y / y
  else
    Result := 0;
end;

const
  FilterFunctions: array [TFilter] of TFilterFunction = (Box, Linear,
    Bicubic, Mine, Lanczos, BSpline);

type
  TPrecision = (prLow, prHigh);

const
  PrecisionFacts: array [TPrecision] of integer = ($100, $800);
  PreMultPrecision = 1 shl 2;

  PointCount = 20;
  PointCountMin2 = PointCount - 2;
  PointCountInv = 1 / PointCount;

procedure MakeContributors(r: single; SourceSize, TargetSize: integer;
  SourceStart, SourceFloatwidth: double; Filter: TFilter; precision: TPrecision;
  var Contribs: TContribArray);
// r: Filterradius
var
  xCenter, scale, rr: double;
  x, j: integer;
  x1, x2, x0, x3, delta, dw: double;
  TrueMin, TrueMax, Mx, prec: integer;
  sum, ds: integer;
  FT: TFilterFunction;
begin
  if SourceFloatwidth = 0 then
    SourceFloatwidth := SourceSize;
  scale := SourceFloatwidth / TargetSize;
  prec := PrecisionFacts[precision];
  SetLength(Contribs, TargetSize);

  FT := FilterFunctions[Filter];

  if scale > 1 then
    // downsampling
    rr := r * scale
  else
    // upsampling
    rr := r;
  delta := 1 / rr;
  if scale = 1 then
  begin
    for x := 0 to TargetSize - 1 do
    begin
      Contribs[x].Min := x;
      Contribs[x].High := 0;
      SetLength(Contribs[x].Weights, 1);
      Contribs[x].Weights[0] := prec;
    end;
    exit;
  end;
  for x := 0 to TargetSize - 1 do
  begin
    xCenter := (x + 0.5) * scale;
    TrueMin := Ceil(xCenter - rr + SourceStart - 1);
    TrueMax := Floor(xCenter + rr + SourceStart);
    Contribs[x].Min := Min(max(TrueMin, 0), SourceSize - 1);
    // make sure not to read in negative pixel locations
    Mx := max(Min(TrueMax, SourceSize - 1), 0);
    // make sure not to read past w1-1 in the source
    Contribs[x].High := Mx - Contribs[x].Min;
    Assert(Contribs[x].High >= 0);
    // High=Number of contributing pixels minus 1
    SetLength(Contribs[x].Weights, Contribs[x].High + 1);
    // SetLength(WeightsF,Contribs[x].High+1);
    sum := 0;
    with Contribs[x] do
    begin
      x0 := delta * (Min - SourceStart - xCenter + 0.5);
      for j := 0 to High do
      begin
        x1 := x0 - 0.5 * delta;
        x2 := x0 + 0.5 * delta;
        // intersect interval [x1, x2] with the support of the filter
        x1 := max(x1, -1);
        x2 := System.Math.Min(x2, 1);
        // x3 is the new center
        x3 := 0.5 * (x1 + x2);
        // evaluate integral_x1^x2 FT(x) dx using a mixture of
        // the midpoint rule and the trapezoidal rule
        // the midpoint parts seems to preserve details
        // while the trapezoidal part and the intersection
        // with the support of the filter prevents artefacts
        dw := PointCountInv * (x2 - x1) *
          (FT(x1) + FT(x2) + PointCountMin2 * FT(x3));
        // scale float to integer, integer=prec corresponds to float=1
        Weights[j] := round(prec * dw);
        x0 := x0 + delta;
        sum := sum + Weights[j];
      end;
      for j := TrueMin - Min to -1 do
      begin
        // assume the first pixel to be repeated
        x0 := delta * (Min + j - SourceStart - xCenter + 0.5);
        x1 := x0 - 0.5 * delta;
        x2 := x0 + 0.5 * delta;
        x1 := max(x1, -1);
        x2 := System.Math.Min(x2, 1);
        x3 := 0.5 * (x1 + x2);
        dw := PointCountInv * (x2 - x1) *
          (FT(x1) + FT(x2) + PointCountMin2 * FT(x3));
        ds := round(dw);
        Weights[0] := Weights[0] + ds;
        sum := sum + ds;
      end;
      for j := High + 1 to TrueMax - Min do
      begin
        // assume the last pixel to be repeated
        x0 := delta * (Min + j - SourceStart - xCenter + 0.5);
        x1 := x0 - 0.5 * delta;
        x2 := x0 + 0.5 * delta;
        x1 := max(x1, -1);
        x2 := System.Math.Min(x2, 1);
        x3 := 0.5 * (x1 + x2);
        dw := PointCountInv * (x2 - x1) *
          (FT(x1) + FT(x2) + PointCountMin2 * FT(x3));
        ds := round(dw);
        Weights[High] := Weights[High] + ds;
        sum := sum + ds;
      end;
      // make sure weights sum up to prec
      Weights[High div 2] := Weights[High div 2] + prec - sum;
    end;
    { with Contribs[x] }
  end; { for x }
end;

// By using 3 different versions of ProcessRow, these are inlined
Procedure CombineIndependent(const ps: PRGBQuad; const Weight: integer;
  const Cache: PBGRAInt); inline;
begin
  Cache.b := Weight * ps.rgbBlue;
  Cache.g := Weight * ps.rgbGreen;
  Cache.r := Weight * ps.rgbRed;
  Cache.a := Weight * ps.rgbReserved;
end;

Procedure CombineIgnore(const ps: PRGBQuad; const Weight: integer;
  const Cache: PBGRAInt); inline;
begin
  Cache.b := Weight * ps.rgbBlue;
  Cache.g := Weight * ps.rgbGreen;
  Cache.r := Weight * ps.rgbRed;
end;

Procedure CombinePremult(const ps: PRGBQuad; const Weight: integer;
  const Cache: PBGRAInt); inline;
begin
  var
  alpha := Weight * ps.rgbReserved;
  Cache.b := ps.rgbBlue * alpha div PreMultPrecision;
  Cache.g := ps.rgbGreen * alpha div PreMultPrecision;
  Cache.r := ps.rgbRed * alpha div PreMultPrecision;
  Cache.a := alpha;
end;

Procedure IncreaseIndependent(const ps: PRGBQuad; const Weight: integer;
  const Cache: PBGRAInt); inline;
begin
  inc(Cache.b, Weight * ps.rgbBlue);
  inc(Cache.g, Weight * ps.rgbGreen);
  inc(Cache.r, Weight * ps.rgbRed);
  inc(Cache.a, Weight * ps.rgbReserved);
end;

Procedure IncreaseIgnore(const ps: PRGBQuad; const Weight: integer;
  const Cache: PBGRAInt); inline;
begin
  inc(Cache.b, Weight * ps.rgbBlue);
  inc(Cache.g, Weight * ps.rgbGreen);
  inc(Cache.r, Weight * ps.rgbRed);
end;

Procedure IncreasePremult(const ps: PRGBQuad; const Weight: integer;
  const Cache: PBGRAInt); inline;
begin
  var
  alpha := Weight * ps.rgbReserved;
  inc(Cache.b, ps.rgbBlue * alpha div PreMultPrecision);
  inc(Cache.g, ps.rgbGreen * alpha div PreMultPrecision);
  inc(Cache.r, ps.rgbRed * alpha div PreMultPrecision);
  inc(Cache.a, alpha);
end;

procedure InitTotal(const Cache: PBGRAInt; const Weight: integer;
  var Total: TBGRAInt); inline;
begin
  Total.b := Weight * Cache.b;
  Total.g := Weight * Cache.g;
  Total.r := Weight * Cache.r;
  Total.a := Weight * Cache.a;
end;

procedure InitTotalIgnore(const Cache: PBGRAInt; const Weight: integer;
  var Total: TBGRAInt); inline;
begin
  Total.b := Weight * Cache.b;
  Total.g := Weight * Cache.g;
  Total.r := Weight * Cache.r;
end;

procedure IncreaseTotal(const Cache: PBGRAInt; const Weight: integer;
  var Total: TBGRAInt); inline;
begin
  inc(Total.b, Weight * Cache.b);
  inc(Total.g, Weight * Cache.g);
  inc(Total.r, Weight * Cache.r);
  inc(Total.a, Weight * Cache.a);
end;

procedure IncreaseTotalIgnore(const Cache: PBGRAInt; const Weight: integer;
  var Total: TBGRAInt); inline;
begin
  inc(Total.b, Weight * Cache.b);
  inc(Total.g, Weight * Cache.g);
  inc(Total.r, Weight * Cache.r);
end;

procedure ClampIndependent(const Total: TBGRAInt; const pT: PRGBQuad); inline;
begin
  pT.rgbBlue := Min((max(Total.b, 0) + $1FFFFF) shr 22, 255);
  pT.rgbGreen := Min((max(Total.g, 0) + $1FFFFF) shr 22, 255);
  pT.rgbRed := Min((max(Total.r, 0) + $1FFFFF) shr 22, 255);
  pT.rgbReserved := Min((max(Total.a, 0) + $1FFFFF) shr 22, 255);
end;

procedure ClampIgnore(const Total: TBGRAInt; const pT: PRGBQuad); inline;
begin
  pT.rgbBlue := Min((max(Total.b, 0) + $1FFFFF) shr 22, 255);
  pT.rgbGreen := Min((max(Total.g, 0) + $1FFFFF) shr 22, 255);
  pT.rgbRed := Min((max(Total.r, 0) + $1FFFFF) shr 22, 255);
end;

procedure ClampPreMult(const Total: TBGRAInt; const pT: PRGBQuad); inline;
var
  alpha: byte;
begin
  alpha := Min((max(Total.a, 0) + $7FFF) shr 16, 255);
  if alpha > 0 then
  begin
    pT.rgbBlue := Min((max(Total.b div alpha, 0) + $1FFF) shr 14, 255);
    pT.rgbGreen := Min((max(Total.g div alpha, 0) + $1FFF) shr 14, 255);
    pT.rgbRed := Min((max(Total.r div alpha, 0) + $1FFF) shr 14, 255);
    pT.rgbReserved := alpha;
  end
  else
    pT^ := Default (TRGBQuad);
end;

type
  TCombineProcedure = procedure(const ps: PRGBQuad; const Weight: integer;
    const Cache: PBGRAInt);
  TTotalProcedure = procedure(const Cache: PBGRAInt; const Weight: integer;
    var Total: TBGRAInt);
  TClampProcedure = procedure(const Total: TBGRAInt; const pT: PRGBQuad);

  TRowProcedure = procedure(y, Sbps, Tbps, xminSource, xmaxSource, xmin,
    xmax: integer; rStart, rTStart: PByte; runstart: PBGRAInt;
    const ContribsX, ContribsY: TContribArray);

{
  const
    CombineInits: array [TAlphaCombineMode] of TCombineProcedure =
      (CombineIndependent, CombinePremult, CombineIgnore);
    CombineIncreases: array [TAlphaCombineMode] of TCombineProcedure =
      (IncreaseIndependent, IncreasePremult, IncreaseIgnore);
    TotalInits: array [TAlphaCombineMode] of TTotalProcedure = (InitTotal,
      InitTotal, InitTotalIgnore);
    TotalIncreases: array [TAlphaCombineMode] of TTotalProcedure = (IncreaseTotal,
      IncreaseTotal, IncreaseTotalIgnore);
    ClampProcedures: array [TAlphaCombineMode] of TClampProcedure =
      (ClampIndependent, ClampPreMult, ClampIgnore);
}

procedure ProcessRowIndependent(y, Sbps, Tbps, xminSource, xmaxSource, xmin,
  xmax: integer; rStart, rTStart: PByte; runstart: PBGRAInt;
  const ContribsX, ContribsY: TContribArray);
var
  ps, pT: PRGBQuad;
  rs, rT: PByte;
  x, i, j: integer;
  highx, highy, minx, miny: integer;
  Weightx, Weighty: PInteger;
  Weight: integer;
  Total: TBGRAInt;
  run: PBGRAInt;
  // CombineInit, CombineIncrease: TCombineProcedure;
  // TotalInit, TotalIncrease: TTotalProcedure;
  // ClampProcedure: TClampProcedure;
begin
  // These procedural variables caused too much of a slowdown.
  // CombineInit := CombineInits[AlphaCombineMode];
  // CombineIncrease := CombineIncreases[AlphaCombineMode];
  // TotalInit := TotalInits[AlphaCombineMode];
  // TotalIncrease := TotalIncreases[AlphaCombineMode];
  // ClampProcedure := ClampProcedures[AlphaCombineMode];

  miny := ContribsY[y].Min;
  highy := ContribsY[y].High;
  rs := rStart;
  rT := rTStart;
  Dec(rs, Sbps * miny);
  Dec(rT, Tbps * y);
  inc(rs, 4 * xminSource);
  Weighty := @ContribsY[y].Weights[0];
  ps := PRGBQuad(rs);
  run := runstart;
  Weight := Weighty^;
  for x := xminSource to xmaxSource do
  begin

    CombineIndependent(ps, Weight, run);

    inc(ps);
    inc(run);
  end; // for x
  inc(Weighty);
  Dec(rs, Sbps);
  for j := 1 to highy do
  begin
    ps := PRGBQuad(rs);
    run := runstart;
    Weight := Weighty^;
    for x := xminSource to xmaxSource do
    begin

      IncreaseIndependent(ps, Weight, run);

      inc(ps);
      inc(run);
    end; // for x
    inc(Weighty);
    Dec(rs, Sbps);
  end; // for j
  pT := PRGBQuad(rT);
  inc(pT, xmin);
  run := runstart;
  var
    jump: integer := xminSource;
  for x := xmin to xmax do
  begin
    minx := ContribsX[x].Min;
    highx := ContribsX[x].High;
    Weightx := @ContribsX[x].Weights[0];
    inc(run, minx - jump);

    InitTotal(run, Weightx^, Total);

    inc(Weightx);
    inc(run);
    for i := 1 to highx do
    begin

      IncreaseTotal(run, Weightx^, Total);

      inc(Weightx);
      inc(run);
    end;
    jump := highx + 1 + minx;

    ClampIndependent(Total, pT);

    inc(pT);
  end; // for x
end;

procedure ProcessRowPreMult(y, Sbps, Tbps, xminSource, xmaxSource, xmin,
  xmax: integer; rStart, rTStart: PByte; runstart: PBGRAInt;
  const ContribsX, ContribsY: TContribArray);
var
  ps, pT: PRGBQuad;
  rs, rT: PByte;
  x, i, j: integer;
  highx, highy, minx, miny: integer;
  Weightx, Weighty: PInteger;
  Weight: integer;
  Total: TBGRAInt;
  run: PBGRAInt;

begin

  miny := ContribsY[y].Min;
  highy := ContribsY[y].High;
  rs := rStart;
  rT := rTStart;
  Dec(rs, Sbps * miny);
  Dec(rT, Tbps * y);
  inc(rs, 4 * xminSource);
  Weighty := @ContribsY[y].Weights[0];
  ps := PRGBQuad(rs);
  run := runstart;
  Weight := Weighty^;

  for x := xminSource to xmaxSource do
  begin
    if ps.rgbReserved > 0 then
      CombinePremult(ps, Weight, run)
    else
      run^ := Default (TBGRAInt);
    inc(ps);
    inc(run);
  end; // for x
  inc(Weighty);
  Dec(rs, Sbps);
  for j := 1 to highy do
  begin
    ps := PRGBQuad(rs);
    run := runstart;
    Weight := Weighty^;
    for x := xminSource to xmaxSource do
    begin
      if ps.rgbReserved > 0 then
        IncreasePremult(ps, Weight, run);
      inc(ps);
      inc(run);
    end; // for x
    inc(Weighty);
    Dec(rs, Sbps);
  end; // for j
  pT := PRGBQuad(rT);
  inc(pT, xmin);
  run := runstart;
  var
    jump: integer := xminSource;
  for x := xmin to xmax do
  begin
    minx := ContribsX[x].Min;
    highx := ContribsX[x].High;
    Weightx := @ContribsX[x].Weights[0];
    inc(run, minx - jump);
    if run.a <> 0 then
      InitTotal(run, Weightx^, Total)
    else
      Total := Default (TBGRAInt);

    inc(Weightx);
    inc(run);
    for i := 1 to highx do
    begin
      if run.a <> 0 then
        IncreaseTotal(run, Weightx^, Total);

      inc(Weightx);
      inc(run);
    end;
    jump := highx + 1 + minx;

    ClampPreMult(Total, pT);

    inc(pT);
  end; // for x
end;

procedure ProcessRowIgnore(y, Sbps, Tbps, xminSource, xmaxSource, xmin,
  xmax: integer; rStart, rTStart: PByte; runstart: PBGRAInt;
  const ContribsX, ContribsY: TContribArray);
var
  ps, pT: PRGBQuad;
  rs, rT: PByte;
  x, i, j: integer;
  highx, highy, minx, miny: integer;
  Weightx, Weighty: PInteger;
  Weight: integer;
  Total: TBGRAInt;
  run: PBGRAInt;
begin
  miny := ContribsY[y].Min;
  highy := ContribsY[y].High;
  rs := rStart;
  rT := rTStart;
  Dec(rs, Sbps * miny);
  Dec(rT, Tbps * y);
  inc(rs, 4 * xminSource);
  Weighty := @ContribsY[y].Weights[0];
  ps := PRGBQuad(rs);
  run := runstart;
  Weight := Weighty^;
  for x := xminSource to xmaxSource do
  begin

    CombineIgnore(ps, Weight, run);

    inc(ps);
    inc(run);
  end; // for x
  inc(Weighty);
  Dec(rs, Sbps);
  for j := 1 to highy do
  begin
    ps := PRGBQuad(rs);
    run := runstart;
    Weight := Weighty^;
    for x := xminSource to xmaxSource do
    begin

      IncreaseIgnore(ps, Weight, run);

      inc(ps);
      inc(run);
    end; // for x
    inc(Weighty);
    Dec(rs, Sbps);
  end; // for j
  pT := PRGBQuad(rT);
  inc(pT, xmin);
  run := runstart;
  var
    jump: integer := xminSource;
  for x := xmin to xmax do
  begin
    minx := ContribsX[x].Min;
    highx := ContribsX[x].High;
    Weightx := @ContribsX[x].Weights[0];
    inc(run, minx - jump);

    InitTotalIgnore(run, Weightx^, Total);

    inc(Weightx);
    inc(run);
    for i := 1 to highx do
    begin

      IncreaseTotalIgnore(run, Weightx^, Total);

      inc(Weightx);
      inc(run);
    end;
    jump := highx + 1 + minx;

    ClampIgnore(Total, pT);

    inc(pT);
  end; // for x
end;

const
  Precisions: array [TAlphaCombineMode] of TPrecision = (prHigh, prLow, prHigh);

  RowProcedures: array [TAlphaCombineMode] of TRowProcedure =
    (ProcessRowIndependent, ProcessRowPreMult, ProcessRowIgnore);

function GetResampleTask(Sbps, Tbps, ymin, ymax, xmin, xmax, xminSource,
  xmaxSource: integer; rStart, rTStart: PByte; runstart: PBGRAInt;
  const ContribsX, ContribsY: TContribArray;
  AlphaCombineMode: TAlphaCombineMode): TProc;
begin
  Result := procedure
    var
      y: integer;
      RP: TRowProcedure;
    begin
      RP := RowProcedures[AlphaCombineMode];
      for y := ymin to ymax do
      begin
        RP(y, Sbps, Tbps, xminSource, xmaxSource, xmin, xmax, rStart, rTStart,
          runstart, ContribsX, ContribsY);

      end; // for y
    end; // procedure
end;

procedure ZoomResampleParallelThreads(NewWidth, NewHeight: integer;
  const Source, Target: TBitmap; SourceRect: TFloatRect; Filter: TFilter;
  Radius: single; AlphaCombineMode: TAlphaCombineMode);
var
  ContribsX, ContribsY: TContribArray;

  OldWidth, OldHeight: integer;

  Sbps, Tbps: integer;
  rStart, rTStart: PByte;
  // Row start in Source, Target
  Index, i, j: integer;
  ThreadCount, xChunkCount, yChunkCount, xChunk, yChunk, xminl, xmaxl,
    xminSourcel, xmaxSourcel: integer;
  CacheMatrix: array of TBGRAIntArray;
  xmin, xmax, xminSource, xmaxSource, ymin, ymax: array of integer;
begin
  if Radius=0 then
  Radius:=DefaultRadius[Filter];
  Source.PixelFormat := pf32bit;
  Target.PixelFormat := pf32bit;
  Target.SetSize(NewWidth, NewHeight);

  OldWidth := Source.Width;
  OldHeight := Source.Height;

  Tbps := ((NewWidth * 32 + 31) and not 31) div 8;
  Sbps := ((OldWidth * 32 + 31) and not 31) div 8;

  MakeContributors(Radius, OldWidth, NewWidth, SourceRect.Left,
    SourceRect.Right - SourceRect.Left, Filter,
    Precisions[AlphaCombineMode], ContribsX);
  MakeContributors(Radius, OldHeight, NewHeight, SourceRect.Top,
    SourceRect.Bottom - SourceRect.Top, Filter,
    Precisions[AlphaCombineMode], ContribsY);

  rStart := Source.ScanLine[0];
  rTStart := Target.ScanLine[0];

  xChunkCount := max(Min(NewWidth div _ChunkWidth, Length(ResamplingThreads)
    div 4), 1);
  yChunkCount := max(Min(NewHeight div _ChunkHeight, Length(ResamplingThreads)
    div xChunkCount), 2);
  ThreadCount := xChunkCount * yChunkCount;

  SetLength(xmin, ThreadCount);
  SetLength(xmax, ThreadCount);
  SetLength(xminSource, ThreadCount);
  SetLength(xmaxSource, ThreadCount);
  SetLength(ymin, ThreadCount);
  SetLength(ymax, ThreadCount);

  xChunk := NewWidth div xChunkCount;
  yChunk := NewHeight div yChunkCount;

  for i := 0 to xChunkCount - 1 do
  begin
    xminl := i * xChunk;
    if i < xChunkCount - 1 then
      xmaxl := (i + 1) * xChunk - 1
    else
      xmaxl := NewWidth - 1;
    xminSourcel := ContribsX[xminl].Min;
    xmaxSourcel := ContribsX[xmaxl].Min + ContribsX[xmaxl].High;
    for j := 0 to yChunkCount - 1 do
    begin
      xmin[i * yChunkCount + j] := xminl;
      xmax[i * yChunkCount + j] := xmaxl;
      xminSource[i * yChunkCount + j] := xminSourcel;
      xmaxSource[i * yChunkCount + j] := xmaxSourcel;
      ymin[i * yChunkCount + j] := j * yChunk;
      if j < yChunkCount - 1 then
        ymax[i * yChunkCount + j] := (j + 1) * yChunk - 1
      else
        ymax[i * yChunkCount + j] := NewHeight - 1;
    end;
  end;

  SetLength(CacheMatrix, ThreadCount);
  for Index := 0 to ThreadCount - 1 do
    SetLength(CacheMatrix[Index], xmaxSource[Index] - xminSource[Index] + 1);

  for Index := 0 to ThreadCount - 1 do
  begin
    ResamplingThreads[Index].RunAnonProc(GetResampleTask(Sbps, Tbps,
      ymin[Index], ymax[Index], xmin[Index], xmax[Index], xminSource[Index],
      xmaxSource[Index], rStart, rTStart, @CacheMatrix[Index][0], ContribsX,
      ContribsY, AlphaCombineMode));
  end;
  for Index := 0 to ThreadCount - 1 do
  begin
    ResamplingThreads[Index].Done.Waitfor(INFINITE);
  end;
end;

procedure ZoomResampleParallelTasks(NewWidth, NewHeight: integer;
  const Source, Target: TBitmap; SourceRect: TFloatRect; Filter: TFilter;
  Radius: single; AlphaCombineMode: TAlphaCombineMode);
var
  ContribsX, ContribsY: TContribArray;

  OldWidth, OldHeight: integer;

  Sbps, Tbps: integer;
  rStart, rTStart: PByte;
  // Row start in Source, Target
  Index, i, j: integer;
  ThreadCount, xChunkCount, yChunkCount, xChunk, yChunk, xminl, xmaxl,
    xminSourcel, xmaxSourcel: integer;
  CacheMatrix: array of TBGRAIntArray;
  xmin, xmax, xminSource, xmaxSource, ymin, ymax: array of integer;
  tasks: array of iTask;
begin
  if Radius=0 then
  Radius:=DefaultRadius[Filter];
  Source.PixelFormat := pf32bit;
  Target.PixelFormat := pf32bit;
  Target.SetSize(NewWidth, NewHeight);

  OldWidth := Source.Width;
  OldHeight := Source.Height;

  Tbps := ((NewWidth * 32 + 31) and not 31) div 8;
  Sbps := ((OldWidth * 32 + 31) and not 31) div 8;

  MakeContributors(Radius, OldWidth, NewWidth, SourceRect.Left,
    SourceRect.Right - SourceRect.Left, Filter,
    Precisions[AlphaCombineMode], ContribsX);
  MakeContributors(Radius, OldHeight, NewHeight, SourceRect.Top,
    SourceRect.Bottom - SourceRect.Top, Filter,
    Precisions[AlphaCombineMode], ContribsY);

  rStart := Source.ScanLine[0];
  rTStart := Target.ScanLine[0];

  xChunkCount := max(Min(NewWidth div _ChunkWidth, Length(ResamplingThreads)
    div 4), 1);
  yChunkCount := max(Min(NewHeight div _ChunkHeight, Length(ResamplingThreads)
    div xChunkCount), 2);
  ThreadCount := xChunkCount * yChunkCount;

  SetLength(xmin, ThreadCount);
  SetLength(xmax, ThreadCount);
  SetLength(xminSource, ThreadCount);
  SetLength(xmaxSource, ThreadCount);
  SetLength(ymin, ThreadCount);
  SetLength(ymax, ThreadCount);

  xChunk := NewWidth div xChunkCount;
  yChunk := NewHeight div yChunkCount;

  for i := 0 to xChunkCount - 1 do
  begin
    xminl := i * xChunk;
    if i < xChunkCount - 1 then
      xmaxl := (i + 1) * xChunk - 1
    else
      xmaxl := NewWidth - 1;
    xminSourcel := ContribsX[xminl].Min;
    xmaxSourcel := ContribsX[xmaxl].Min + ContribsX[xmaxl].High;
    for j := 0 to yChunkCount - 1 do
    begin
      xmin[i * yChunkCount + j] := xminl;
      xmax[i * yChunkCount + j] := xmaxl;
      xminSource[i * yChunkCount + j] := xminSourcel;
      xmaxSource[i * yChunkCount + j] := xmaxSourcel;
      ymin[i * yChunkCount + j] := j * yChunk;
      if j < yChunkCount - 1 then
        ymax[i * yChunkCount + j] := (j + 1) * yChunk - 1
      else
        ymax[i * yChunkCount + j] := NewHeight - 1;
    end;
  end;

  SetLength(CacheMatrix, ThreadCount);
  for Index := 0 to ThreadCount - 1 do
    SetLength(CacheMatrix[Index], xmaxSource[Index] - xminSource[Index] + 1);
  SetLength(tasks, ThreadCount);
  for Index := 0 to ThreadCount - 1 do
  begin
    tasks[Index] := TTask.Run(GetResampleTask(Sbps, Tbps,
      ymin[Index], ymax[Index], xmin[Index], xmax[Index], xminSource[Index],
      xmaxSource[Index], rStart, rTStart, @CacheMatrix[Index][0], ContribsX,
      ContribsY, AlphaCombineMode));
  end;
  TTask.WaitForAll(tasks,INFINITE);
end;

procedure ZoomResample(NewWidth, NewHeight: integer;
  const Source, Target: TBitmap; SourceRect: TFloatRect; Filter: TFilter;
  Radius: single; AlphaCombineMode: TAlphaCombineMode);
var
  ContribsX, ContribsY: TContribArray;

  OldWidth, OldHeight, SourceMin, SourceMax: integer;

  Sbps, Tbps: integer;
  rStart, rTStart: PByte;
  // Row start in Source, Target
  Cache: TBGRAIntArray; // cache  of integer valued bgra
  y: integer;
  runstart: PBGRAInt;
  RP: TRowProcedure;
begin
  if Radius=0 then
  Radius:=DefaultRadius[Filter];
  Source.PixelFormat := pf32bit;
  Target.PixelFormat := pf32bit;
  Target.SetSize(NewWidth, NewHeight);

  OldWidth := Source.Width;
  OldHeight := Source.Height;

  Tbps := ((NewWidth * 32 + 31) and not 31) div 8;
  Sbps := ((OldWidth * 32 + 31) and not 31) div 8;

  MakeContributors(Radius, OldWidth, NewWidth, SourceRect.Left,
    SourceRect.Right - SourceRect.Left, Filter,
    Precisions[AlphaCombineMode], ContribsX);
  MakeContributors(Radius, OldHeight, NewHeight, SourceRect.Top,
    SourceRect.Bottom - SourceRect.Top, Filter,
    Precisions[AlphaCombineMode], ContribsY);

  rStart := Source.ScanLine[0];
  rTStart := Target.ScanLine[0];

  SourceMin := ContribsX[0].Min;
  SourceMax := ContribsX[NewWidth - 1].Min + ContribsX[NewWidth - 1].High;

  SetLength(Cache, SourceMax - SourceMin + 1);
  runstart := @Cache[0];

  RP := RowProcedures[AlphaCombineMode];

  // Compute colors for each target row at y
  for y := 0 to NewHeight - 1 do
  begin
    RP(y, Sbps, Tbps, SourceMin, SourceMax, 0, NewWidth - 1, rStart, rTStart,
      runstart, ContribsX, ContribsY);
  end;
  // for y
end;

procedure Resample(NewWidth, NewHeight: integer; const Source, Target: TBitmap;
Filter: TFilter; Radius: single; parallel: boolean;
AlphaCombineMode: TAlphaCombineMode);
var
  r: TFloatRect;
begin
  r := FloatRect(Rect(0, 0, Source.Width, Source.Height));
  if parallel then

    ZoomResampleParallelThreads(NewWidth, NewHeight, Source, Target, r, Filter,
      Radius, AlphaCombineMode)

  else

    ZoomResample(NewWidth, NewHeight, Source, Target, r, Filter, Radius,
      AlphaCombineMode);

end;

{ TResamplingThread }

constructor TResamplingThread.Create;
begin
  inherited Create(false);
  FreeOnTerminate := false;
  Wakeup := TEvent.Create;
  Done := TEvent.Create;
  Ready := TEvent.Create;
end;

destructor TResamplingThread.Destroy;
begin
  Wakeup.Free;
  Done.Free;
  Ready.Free;
  inherited;
end;

procedure TResamplingThread.Execute;
begin
  While not terminated do
  begin
    Ready.SetEvent;
    Wakeup.Waitfor(INFINITE);
    if not terminated then
    begin
      Wakeup.ResetEvent;
      fResamplingThreadProc;
      Done.SetEvent;
    end;
  end;

end;

procedure TResamplingThread.RunAnonProc(aProc: TProc);
begin
  Ready.Waitfor(INFINITE);
  Ready.ResetEvent;
  Done.ResetEvent;
  fResamplingThreadProc := aProc;
  Wakeup.SetEvent;
end;

procedure InitResamplingThreads;
begin
  //creating more threads than processors present does not seem to
  //speed up anything.
  SetLength(ResamplingThreads, Min(MaxThreadCount, TThread.ProcessorCount));

  for var i: integer := 0 to Length(ResamplingThreads) - 1 do
  begin
    ResamplingThreads[i] := TResamplingThread.Create;
    ResamplingThreads[i].priority := tpHigher;
    ResamplingThreads[i].Ready.WaitFor(Infinite);
  end;
end;

procedure FreeResamplingThreads;
begin
  for var i: integer := 0 to Length(ResamplingThreads) - 1 do
  begin
    ResamplingThreads[i].Terminate;
    ResamplingThreads[i].Wakeup.SetEvent;
    ResamplingThreads[i].Free;
    ResamplingThreads[i] := nil;
  end;
  SetLength(ResamplingThreads,0);
end;

initialization

//The threads stay around all the time waiting to be woken up.
//This looks terrible, but hardly consumes any additional CPU-time
//at all. Watch task manager.
InitResamplingThreads;


finalization

FreeResamplingThreads;


{$IFDEF O_MINUS}
{$O-}
{$UNDEF O_MINUS}
{$ENDIF}
{$IFDEF Q_PLUS}
{$Q+}
{$UNDEF Q_PLUS}
{$ENDIF}

end.