#!perl
#
# Input: A crystal or molecule document composed of one unique molecule
# Output: A crystal with the isolated molecule centered in a minimum lattice
#         which is expanded by the user-defined value
# Limitations: The input structure must have only one type of molecule
#
# Steve Monaco
# Materials Studio 7.0
# MakeMoleculeInBox v1.3
#
# First, the centroid of the molecule is determined and translated to the origin.
# Second, the molecule is rotated so that its principal axes are aligned with the document's axes.
# Third, a minimum bounding box is created.
# Fourth, the minimum bounding box is expanded by the user-defined AngstromPadding
# Fifth, a new crystal is made using this information with the molecule's centroid at the center of the crystal.
################################################################################

use strict;
use Getopt::Long;
use MaterialsScript qw(:all);
use Math::Trig;

my %Args;
GetOptions(\%Args, "Distance_to_Nearest_Neighbor=f");
GetOptions(\%Args, "Angstrom_Padding=f");

################################################################################
# User-defined variables
my $input = Documents->ActiveDocument;
my $dist  = $Args{Distance_to_Nearest_Neighbor};
################################################################################

my $AngstromPadding = $dist / 2;
my $output = Documents->New($input->Name . "-box.xsd");

my $atoms = $input->AsymmetricUnit->Atoms->Item(0)->Fragment->Atoms;
my $mol;

if($atoms->Count == 0)
{
	die("No atoms found in structure");
}
else
{
	$mol = $atoms->Item(0)->Fragment;
}

$output->CopyFrom($mol);
$input->Discard(); # Close input file
$mol = $output->Atoms;

# Translate the molecule's centroid to the origin.
my $centroid = $output->CreateCentroid($mol);
$centroid->IsWeighted = "No"; # Geometric midpoint
$mol->Translate(Point( X => -$centroid->CentroidXYZ->X, Y => -$centroid->CentroidXYZ->Y, Z => -$centroid->CentroidXYZ->Z ));
$centroid->Delete();

# Create the principal axes
my $axes = $output->CreatePrincipalAxes($mol);
$axes->IsWeighted = "No";

# Rotate principle axes so they align with the document's axes
my $pa1 = $axes->PrincipalAxis1; # Longest axis
my $angle = rad2deg(acos_real($pa1->X));
my $rotationaxis = Point(X=>0, Y=>$pa1->Z, Z=>-$pa1->Y);
$mol->RotateAboutPoint($angle, $rotationaxis, $axes->CentroidXYZ);

my $pa2 = $axes->PrincipalAxis2;
$angle = rad2deg(acos_real($pa2->Y));
my $rotationaxis = Point(X=>-$pa2->Z , Y=>0, Z=>$pa2->X );
$mol->RotateAboutPoint($angle, $rotationaxis, $axes->CentroidXYZ);
$axes->Delete();

# Create a bounding box which is minimum containment size for atoms and their vdW radius
(my $xmin, my $xmax, my $ymin, my $ymax, my $zmin, my $zmax) = BoundingBox($mol);

# Build a P1 crystal and enlarge the bounding box
Tools->CrystalBuilder->SetSpaceGroup("P1", "");
my $width = ($xmax - $xmin) + $AngstromPadding * 2;
my $height = ($ymax - $ymin) + $AngstromPadding * 2;
my $depth = ($zmax - $zmin) + $AngstromPadding * 2;

Tools->CrystalBuilder->SetCellParameters($width, $height, $depth, 90, 90, 90);
Tools->CrystalBuilder->Build($mol);

# Reposition a molecule to the box's center and rebuild crystal
$mol->Translate(Point(X => $width / 2, Y => $height / 2, Z => $depth / 2 ));
Tools->Symmetry->UnbuildCrystal($output);
Tools->CrystalBuilder->Build($output);
$output->UpdateViews;
$output->Save(); # Close and save the output file
$output->Close;


################################################################################
# Angle = arccos ((a dot b) / (|a| * |b|)) * (pi / 180)
# Where dot is the dot product and |a| is the magnitude (or "norm") of a
# Returns angle in degrees
################################################################################

sub FindAngleBetweenTwoVectors()
{
    my ($a, $b) = @_;
    my $dot = $a->X * $b->X + $a->Y * $b->Y + $a->Z * $b->Z;
    my $amagnitude = sqrt($a->X * $a->X + $a->Y * $a->Y + $a->Z * $a->Z);
    my $bmagnitude = sqrt($b->X * $b->X + $b->Y * $b->Y + $b->Z * $b->Z);
    
    my $angle = $dot / ($amagnitude * $bmagnitude);
    
    return (180 / pi) * acos($angle);
}

################################################################################
# (a, b, c) = A x B
# Returns cross-product of two unit 3D vectors
# A x B = i(AyBz - AzBy) - j(AxBz - AzBx) + k(AxBy - AyBx)
################################################################################

sub FindCrossProduct()
{
    my ($A, $B) = @_;
    my $i = $A->Y * $B->Z - $A->Z * $B->Y;
    my $j = -($A->X * $B->Z - $A->Z * $B->X);
    my $k = $A->X * $B->Y - $A->Y * $B->X;
    return ($i, $j, $k);
}

################################################################################
# Returns coordinates for a minimum, rectangular bounding box
# (no parallelepipeds), given a list of atoms
################################################################################

sub BoundingBox()
{
    my ($atoms) = @_;
    my $xmin, my $xmax, my $ymin, my $ymax, my $zmin, my $zmax;
    
    foreach my $atom (@$atoms)
    {
        if($atom->X< $xmin)
        {
            $xmin = $atom->X;
        }
        if($atom->X > $xmax)
        {
            $xmax = $atom->X;
        }
        if($atom->Y < $ymin)
        {
            $ymin = $atom->Y;
        }
        if($atom->Y > $ymax)
        {
            $ymax = $atom->Y;
        }
        if($atom->Z < $zmin)
        {
            $zmin = $atom->Z;
        }
        if($atom->Z > $zmax)
        {
            $zmax = $atom->Z;
        }
    }
    
    return ($xmin, $xmax, $ymin, $ymax, $zmin, $zmax);
}