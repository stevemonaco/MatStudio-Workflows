#!perl
#
# Input: Pressure series study table
# Function: Optimizes structures at various pressures and/or calculates properties
#
# Steve Monaco
# Materials Studio 7.0
# CalcPressureSeries v1.3
#
# v1.3  - Added retry error handling (CASTEP calculations can crash midway and cause a script exit)
# v1.2  - Refactored code, GeomOpt + Property calculations no longer require an energy calculation for properties
# v1.12 - Error handling for 0eV band gaps, removed DOS from band gap calc
# v1.1  - Adds band gap calculation option
#
################################################################################

use strict;
use Getopt::Long;
use MaterialsScript qw(:all);

my %Args;
GetOptions(\%Args, "Optimize_All_Structures=s", "GeomOpt_Iterations=i", "Structures_To_Optimize=i",
				"Perform_Optimization=s", "Calculate_BandGap=s", "Property_Row_Start=i",
				"Property_Row_End=i", "Property_Row_Skip=i");

######################################################################
# User variables
#

my $table = Documents->ActiveDocument;
my $CalcNum = $Args{Structures_To_Optimize}; # Number of structures to optimize in series
my $OptimizeStructures = $Args{Perform_Optimization};
my $GeomOptIterations = $Args{GeomOpt_Iterations};
my $OptimizeAll = $Args{Optimize_All_Structures};
my $CalculateBandGap = $Args{Calculate_BandGap};
my $PropertyRowStart = $Args{Property_Row_Start} - 1; # Subtract one because study table rows are 0-based
my $PropertyRowEnd   = $Args{Property_Row_End} - 1;
my $PropertyRowSkip  = $Args{Property_Row_Skip};
my $maxtries = 3;

######################################################################

# Get input structure and result row for next calculation
my $input;
my $OptimizeRowStart;
my $OptimizeRowEnd;
my $RowsSkipped = 0;
my $FirstCalc = 1;
my @proprows = ( );

local $| = 1; # Automatically flush stdout

# Make a list of all rows with property calcs
for(my $i = $PropertyRowStart; $i <= $PropertyRowEnd; $i = $i + $PropertyRowSkip + 1)
{
	push(@proprows, $i);
}

if($OptimizeStructures eq "No" && $CalculateBandGap eq "No")
{
	die("No calculations selected.");
}

# Find first incomplete row
if($OptimizeStructures eq "Yes") # Geometry Optimization
{
	for(my $i = 0; $i < $table->RowCount; $i++)
	{
		if($table->Cell($i, 12) eq "No") # Incomplete
		{
			$OptimizeRowStart = $i;
			last;
		}
	}
}

# Check bounds on $CalcNum
my $OptimizeRowEnd = $OptimizeRowStart + $CalcNum;
if($OptimizeRowEnd > $table->RowCount)
{
	$OptimizeRowEnd = $table->RowCount - 1;
}
if($OptimizeAll eq "Yes")
{
	$OptimizeRowEnd = $table->RowCount - 1;
}

my $try = 1;

# Loop through all table rows
for(my $i = $0; $i < $table->RowCount; $i++)
{
    my $calcprop = FindMatch(\@proprows, $i); # Calculate properties for this row?
    
	if($OptimizeStructures eq "Yes" && $i >= $OptimizeRowStart && $i <= $OptimizeRowEnd) # GeomOpt + Property calc
	{
		my $input = $table->Cell($i - 1, 0); # Input structure is row prior to incomplete calculation
	
		# Create a copy of the structure so we can rename it for use in the next calculation
		my $pressure = $table->Cell($i, 1);
		my $intpressure = $pressure;
		my $intpressure = int($intpressure); # Integer digits
		my $decpressure = int(($pressure - $intpressure) * 100); # First two decimal places
		my $name = sprintf("%s_%02i_%02i", $table->Name, $intpressure, $decpressure);
		my $copy = Documents->New($name . ".xsd");
		$copy->CopyFrom($input);
		$input->Discard;
		
		my $resultdoc = undef;
		my $bandgap = undef;
		
		print("Geometry Optimizing " . $copy->Name . " at " . $pressure . " GPa...");
		
		eval { ($resultdoc, $bandgap) = OptimizeStructure($copy, $pressure, $calcprop); };
		
		if($@) # Error
		{
			print("Failed try " . $try . " of " . $maxtries . "\n");

			$try++; # Test whether to try again
			if($try <= $maxtries)
			{
				$copy->Discard;
				$i--; # Subtract one because one will be added by the for loop
				next;
			}
			else
			{
				print("Max try count exceeded. This script must exit\n");
				exit();
			}
		}
		
		print("Complete.\n");

		$table->Cell($i, 0) = $resultdoc;
		$table->Cell($i, 2) = $resultdoc->SymmetryDefinition->LengthA;
		$table->Cell($i, 3) = $resultdoc->SymmetryDefinition->LengthB;
		$table->Cell($i, 4) = $resultdoc->SymmetryDefinition->LengthC;
		$table->Cell($i, 5) = $resultdoc->SymmetryDefinition->AngleAlpha;
		$table->Cell($i, 6) = $resultdoc->SymmetryDefinition->AngleBeta;
		$table->Cell($i, 7) = $resultdoc->SymmetryDefinition->AngleGamma;
		$table->Cell($i, 8) = $resultdoc->SymmetrySystem->Density;
		$table->Cell($i, 9) = $resultdoc->Lattice3D->CellVolume;
		$table->Cell($i, 10) = $resultdoc->SymmetryDefinition->Name . " [" . $resultdoc->SymmetryDefinition->SpaceGroupSchoenfliesName . "]";
		$table->Cell($i, 12) = "Yes";

		if($calcprop && $CalculateBandGap)
		{
			$table->Cell($i, 11) = $bandgap;
		}

		$try = 1;
		$table->Save;
		$copy->Close;
		$resultdoc->Close;
	}
	elsif($calcprop) # Energy+Property calc
	{
		my $input = $table->Cell($i, 0); # Input structure is in current row

		# Create a copy of the structure to prevent naming conflicts
		my $copy = Documents->New($input->Name . ".Energy.xsd");
		$copy->CopyFrom($input);
		$input->Discard;

		print("Calculating Band Gap for " . $copy->Name . "...");

		my $bandgap = undef;
		eval { $bandgap = CalcBandGap($copy); };

		if($@) # Error
		{
			print("Failed try " . $try . " of " . $maxtries . "\n");

			$try++; # Test whether to try again
			if($try <= $maxtries)
			{
				$copy->Discard;
				$i--; # Subtract one because one will be added by the for loop
				next;
			}
			else
			{
				print("Max try count exceeded. This script must exit\n");
				exit();
			}
		}

		print("Complete.\n");

		$table->Cell($i, 11) = $bandgap;
		$try = 1;
		$table->Save;
		$copy->Close;
	}
}

sub OptimizeStructure()
{
	my ($doc, $pressure, $calcprop) = @_;
	$doc->PrimitiveCell; # Do calc as primitive cell

	my $module = Modules->CASTEP;
	my $bandgap = 0;

	# If more properties are added, remember to reset them here
	# eg. If band gaps are calculated elsewhere, you must set CalculateBandStructure = "None" else the
	# settings from elsewhere will carry over to this calculation

	$module->ChangeSettings(Settings( TheoryLevel => "GGA", NonLocalFunctional => "PBE", UseDFTD => "Yes",
		DFTDMethod => "TS", Quality => "Ultra-fine", Pseudopotentials => "Norm-conserving",
		EnergyCutoffQuality => "Ultra-fine", UseCustomEnergyCutoff => "Yes", EnergyCutoff => 750,
		RuntimeOptimization => "Speed", KPointOverallQuality => "Fine", PropertiesKPointQuality => "Fine",
		UseInsulatorDerivation => "Yes", FixOccupancy => "Yes", CalculateBandStructure => "None",
		MaxIterations => $GeomOptIterations, OptimizeCell => "Yes",
		Sxx => $pressure, Syy => $pressure, Szz => $pressure ));

	if($calcprop) # Apply property settings
	{
		if($CalculateBandGap)
		{
			$module->ChangeSettings(Settings( CalculateBandStructure => "Dispersion"));
		}
	}

	my $results = $module->GeometryOptimization->Run($doc);
	my $resultstructure = $results->Structure;
	$resultstructure->ConventionalCell;

	eval { $bandgap = $results->BandGap; };
	
	if($@) # Error, return 0.0 for band gap
	{
		$bandgap = 0.0;
	}
	
	return ( $resultstructure, $bandgap );
}

sub CalcBandGap()
{
	my ($doc) = @_;
	$doc->PrimitiveCell; # Do calc as primitive cell

	my $module = Modules->CASTEP;

	$module->ChangeSettings(Settings( TheoryLevel => "GGA", NonLocalFunctional => "PBE", UseDFTD => "Yes",
		DFTDMethod => "TS", Quality => "Ultra-fine", Pseudopotentials => "Norm-conserving",
		EnergyCutoffQuality => "Ultra-fine", UseCustomEnergyCutoff => "Yes", EnergyCutoff => 750,
		RuntimeOptimization => "Speed", KPointOverallQuality => "Fine", PropertiesKPointQuality => "Fine",
		UseInsulatorDerivation => "Yes", FixOccupancy => "Yes", CalculateBandStructure => "Dispersion"));

	my $results = $module->Energy->Run($doc);
	my $resultstructure = $results->Structure;
	$resultstructure->ConventionalCell;
	$resultstructure->Save;

	my $bandgap = undef;
	eval { $bandgap = $results->BandGap; };

	if($@) # Error, return 0.0 for band gap
	{
		$bandgap = 0.0;
	}

	return $bandgap;
}

# [0] - Array to search
# [1] - Keyword to find
# Returns 1 if Keyword is within the Array, 0 if it is not

sub FindMatch
{
	my @list = @{$_[0]};
	my $word = $_[1];

	for(my $i = 0; $i <= $#list; $i++)
	{
		if($list[$i] == $word)
		{
			return 1;
		}
	}

	return 0;
}