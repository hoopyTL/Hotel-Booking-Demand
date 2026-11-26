# ==============================================================================
# deploy_ssas_cube.ps1
# Build, Deploy, Process, and Export SSAS Multidimensional OLAP Cube:
#   Server   : .\SSAS (Multidimensional Mode)
#   Database : HotelBooking_OLAP
#   Cube     : Hotel Booking Cube
#   Source   : .\SQLEXPRESS -> HotelBooking_DW (dw.* tables)
# ==============================================================================
param(
    [string]$SsasServer = ".\SSAS",
    [string]$SqlServer = ".\SQLEXPRESS",
    [string]$SqlDatabase = "HotelBooking_DW",
    [string]$OlapDatabase = "HotelBooking_OLAP",
    [string]$ExportXmlaPath = "C:\Users\ADMIN\Desktop\Hotel-Booking-Demand\ssas\HotelBooking_OLAP\HotelBooking_OLAP.xmla"
)

$ErrorActionPreference = "Stop"

# Load AMO Assembly
[void][System.Reflection.Assembly]::LoadWithPartialName("Microsoft.AnalysisServices")

Write-Host "[1/6] Connecting to SSAS Multidimensional Server: $SsasServer ..."
$server = New-Object Microsoft.AnalysisServices.Server
$server.Connect("Data Source=$SsasServer")
if ($server.ServerMode -ne [Microsoft.AnalysisServices.ServerMode]::Multidimensional) {
    throw "SSAS server '$SsasServer' is in $($server.ServerMode) mode. Multidimensional mode is required."
}
Write-Host "      Connected: $($server.Name) ($($server.Edition), $($server.Version), Mode=$($server.ServerMode))"

# Drop existing OLAP database if present (idempotent redeploy)
$existingDb = $server.Databases.FindByName($OlapDatabase)
if ($null -ne $existingDb) {
    Write-Host "[2/6] Dropping existing OLAP database '$OlapDatabase' ..."
    $existingDb.Drop()
} else {
    Write-Host "[2/6] Creating fresh OLAP database '$OlapDatabase' ..."
}

$db = New-Object Microsoft.AnalysisServices.Database($OlapDatabase, $OlapDatabase)
$db.Language = 1033
$server.Databases.Add($db)

# ------------------------------------------------------------------------------
# Data Source
# ------------------------------------------------------------------------------
$ds = New-Object Microsoft.AnalysisServices.RelationalDataSource("HotelBooking_DW", "HotelBooking_DW")
$ds.ConnectionString = "Provider=MSOLEDBSQL;Data Source=$SqlServer;Initial Catalog=$SqlDatabase;Integrated Security=SSPI;"
$ds.ImpersonationInfo = New-Object Microsoft.AnalysisServices.ImpersonationInfo([Microsoft.AnalysisServices.ImpersonationMode]::ImpersonateServiceAccount)
$db.DataSources.Add($ds)

# ------------------------------------------------------------------------------
# Data Source View (DSV) populated from live SQL Server schema
# ------------------------------------------------------------------------------
Write-Host "[3/6] Building Data Source View (HotelBooking_DSV) from $SqlServer.$SqlDatabase ..."
$dsv = New-Object Microsoft.AnalysisServices.DataSourceView("HotelBooking_DSV", "HotelBooking_DSV")
$dsv.DataSourceID = $ds.ID
$schema = New-Object System.Data.DataSet("HotelBooking_DSV")

$dwTables = @(
    "Dim_Date",
    "Dim_Hotel",
    "Dim_Country",
    "Dim_Market_Segment",
    "Dim_Distribution_Channel",
    "Dim_Room_Type",
    "Dim_Booking_Profile",
    "Dim_Reservation_Status",
    "Dim_Agent_Company",
    "Fact_Hotel_Booking",
    "Fact_Daily_Stay_Snapshot"
)

$oleConn = New-Object System.Data.OleDb.OleDbConnection($ds.ConnectionString)
$oleConn.Open()
try {
    foreach ($tbl in $dwTables) {
        $adapter = New-Object System.Data.OleDb.OleDbDataAdapter("SELECT * FROM [dw].[$tbl] WHERE 1=0", $oleConn)
        $dt = New-Object System.Data.DataTable("dw_$tbl")
        [void]$adapter.FillSchema($dt, [System.Data.SchemaType]::Source)
        $dt.ExtendedProperties["DbTableName"] = $tbl
        $dt.ExtendedProperties["FriendlyName"] = $tbl
        $dt.ExtendedProperties["DbSchemaName"] = "dw"
        $dt.ExtendedProperties["TableType"] = "Table"
        $schema.Tables.Add($dt)
    }
} finally {
    $oleConn.Close()
}

# Add Named Calculations to DSV for clean Hierarchies & Aggregations
function Add-NamedCalc([System.Data.DataTable]$table, [string]$colName, [type]$colType, [string]$sqlExpr) {
    $col = New-Object System.Data.DataColumn($colName, $colType)
    $col.ExtendedProperties["DbColumnName"] = $colName
    $col.ExtendedProperties["ComputedColumnExpression"] = $sqlExpr
    $col.ExtendedProperties["IsLogical"] = "True"
    $col.ExtendedProperties["Description"] = "SSAS Named Calculation"
    $table.Columns.Add($col)
}

$dtDate = $schema.Tables["dw_Dim_Date"]
Add-NamedCalc $dtDate "FullDateLabel" ([string]) "CONVERT(CHAR(10), [full_date], 120)"
Add-NamedCalc $dtDate "QuarterLabel" ([string]) "'Q' + CAST([quarter] AS VARCHAR(1)) + '-' + CAST([year] AS VARCHAR(4))"
Add-NamedCalc $dtDate "YearMonth" ([string]) "CONVERT(CHAR(7), [full_date], 120)"
Add-NamedCalc $dtDate "SeasonLabel" ([string]) "CAST([year] AS VARCHAR(4)) + ' - ' + [season]"

$dtFact = $schema.Tables["dw_Fact_Hotel_Booking"]
Add-NamedCalc $dtFact "RoomChangedCount" ([int]) "CAST([is_room_changed] AS INT)"
Add-NamedCalc $dtFact "AdrOutlierCount" ([int]) "CAST([is_adr_outlier] AS INT)"
Add-NamedCalc $dtFact "ZeroGuestCount" ([int]) "CAST([is_zero_guest] AS INT)"
Add-NamedCalc $dtFact "ExactDuplicateCount" ([int]) "CAST([is_exact_duplicate] AS INT)"

# Define DataRelations in DSV
function Add-DsvRel([string]$name, [string]$parentTbl, [string]$parentCol, [string]$childTbl, [string]$childCol) {
    $rel = New-Object System.Data.DataRelation(
        $name,
        $schema.Tables[$parentTbl].Columns[$parentCol],
        $schema.Tables[$childTbl].Columns[$childCol],
        $false
    )
    $schema.Relations.Add($rel)
}

Add-DsvRel "FK_Booking_ArrivalDate" "dw_Dim_Date" "date_key" "dw_Fact_Hotel_Booking" "arrival_date_key"
Add-DsvRel "FK_Booking_BookingDate" "dw_Dim_Date" "date_key" "dw_Fact_Hotel_Booking" "booking_date_key"
Add-DsvRel "FK_Booking_StatusDate" "dw_Dim_Date" "date_key" "dw_Fact_Hotel_Booking" "status_date_key"
Add-DsvRel "FK_Booking_Hotel" "dw_Dim_Hotel" "hotel_key" "dw_Fact_Hotel_Booking" "hotel_key"
Add-DsvRel "FK_Booking_Country" "dw_Dim_Country" "country_key" "dw_Fact_Hotel_Booking" "country_key"
Add-DsvRel "FK_Booking_MarketSegment" "dw_Dim_Market_Segment" "market_segment_key" "dw_Fact_Hotel_Booking" "market_segment_key"
Add-DsvRel "FK_Booking_DistChannel" "dw_Dim_Distribution_Channel" "distribution_channel_key" "dw_Fact_Hotel_Booking" "distribution_channel_key"
Add-DsvRel "FK_Booking_ReservedRoom" "dw_Dim_Room_Type" "room_type_key" "dw_Fact_Hotel_Booking" "reserved_room_type_key"
Add-DsvRel "FK_Booking_AssignedRoom" "dw_Dim_Room_Type" "room_type_key" "dw_Fact_Hotel_Booking" "assigned_room_type_key"
Add-DsvRel "FK_Booking_Profile" "dw_Dim_Booking_Profile" "booking_profile_key" "dw_Fact_Hotel_Booking" "booking_profile_key"
Add-DsvRel "FK_Booking_Status" "dw_Dim_Reservation_Status" "reservation_status_key" "dw_Fact_Hotel_Booking" "reservation_status_key"
Add-DsvRel "FK_Booking_AgentCompany" "dw_Dim_Agent_Company" "agent_company_key" "dw_Fact_Hotel_Booking" "agent_company_key"

Add-DsvRel "FK_Daily_StayDate" "dw_Dim_Date" "date_key" "dw_Fact_Daily_Stay_Snapshot" "stay_date_key"
Add-DsvRel "FK_Daily_Hotel" "dw_Dim_Hotel" "hotel_key" "dw_Fact_Daily_Stay_Snapshot" "hotel_key"
Add-DsvRel "FK_Daily_AssignedRoom" "dw_Dim_Room_Type" "room_type_key" "dw_Fact_Daily_Stay_Snapshot" "assigned_room_type_key"
Add-DsvRel "FK_Daily_MarketSegment" "dw_Dim_Market_Segment" "market_segment_key" "dw_Fact_Daily_Stay_Snapshot" "market_segment_key"
Add-DsvRel "FK_Daily_Profile" "dw_Dim_Booking_Profile" "booking_profile_key" "dw_Fact_Daily_Stay_Snapshot" "booking_profile_key"

$dsv.Schema = $schema
$db.DataSourceViews.Add($dsv)

# ------------------------------------------------------------------------------
# Helper functions to create AMO DataItems, Attributes, Hierarchies
# ------------------------------------------------------------------------------
function New-DataItem([System.Data.DataTable]$dt, [string]$colName) {
    $col = $dt.Columns[$colName]
    if ($null -eq $col) { throw "Column '$colName' not found in table '$($dt.TableName)'" }
    $oledbType = [Microsoft.AnalysisServices.OleDbTypeConverter]::GetRestrictedOleDbType($col.DataType)
    $di = New-Object Microsoft.AnalysisServices.DataItem($dt.TableName, $colName, $oledbType)
    if ($col.DataType -eq [string] -and $col.MaxLength -gt 0) {
        $di.DataSize = $col.MaxLength
    }
    return $di
}

function Add-DimAttribute(
    [Microsoft.AnalysisServices.Dimension]$dim,
    [System.Data.DataTable]$dt,
    [string]$attrName,
    [string]$keyCol,
    [string]$nameCol = $null,
    [bool]$isKey = $false
) {
    $attr = New-Object Microsoft.AnalysisServices.DimensionAttribute($attrName, $attrName)
    $attr.KeyColumns.Add((New-DataItem $dt $keyCol)) | Out-Null
    if ($nameCol) {
        $attr.NameColumn = New-DataItem $dt $nameCol
    }
    if ($isKey) {
        $attr.Usage = [Microsoft.AnalysisServices.AttributeUsage]::Key
    }
    $dim.Attributes.Add($attr) | Out-Null
    return $attr
}

function Add-Hierarchy(
    [Microsoft.AnalysisServices.Dimension]$dim,
    [string]$hName,
    [string[]]$levelAttrNames
) {
    $h = New-Object Microsoft.AnalysisServices.Hierarchy($hName, $hName)
    foreach ($la in $levelAttrNames) {
        $lvl = New-Object Microsoft.AnalysisServices.Level($la, $la)
        $lvl.SourceAttributeID = $dim.Attributes.GetByName($la).ID
        $h.Levels.Add($lvl) | Out-Null
    }
    $dim.Hierarchies.Add($h) | Out-Null
    return $h
}

# ------------------------------------------------------------------------------
# Build 9 Dimensions
# ------------------------------------------------------------------------------
Write-Host "[4/6] Creating 9 Multidimensional Dimensions & Hierarchies ..."

# 1. Dim Date
$dimDate = New-Object Microsoft.AnalysisServices.Dimension("Dim Date", "Dim Date")
$dimDate.Source = New-Object Microsoft.AnalysisServices.DataSourceViewBinding($dsv.ID)
$dimDate.Type = [Microsoft.AnalysisServices.DimensionType]::Time
$aDateKey = Add-DimAttribute $dimDate $dtDate "Date Key" "date_key" "FullDateLabel" $true
$aYear = Add-DimAttribute $dimDate $dtDate "Year" "year"
$aQuarter = Add-DimAttribute $dimDate $dtDate "Quarter" "quarter"
$aQuarterLbl = Add-DimAttribute $dimDate $dtDate "Quarter Label" "QuarterLabel"
$aMonthNum = Add-DimAttribute $dimDate $dtDate "Month Number" "month_number"
$aMonthName = Add-DimAttribute $dimDate $dtDate "Month Name" "month_name"
$aYearMonth = Add-DimAttribute $dimDate $dtDate "Year Month" "YearMonth"
$aSeason = Add-DimAttribute $dimDate $dtDate "Season" "season"
$aSeasonLbl = Add-DimAttribute $dimDate $dtDate "Season Label" "SeasonLabel"
$aIsWeekend = Add-DimAttribute $dimDate $dtDate "Is Weekend" "is_weekend"
$aDayName = Add-DimAttribute $dimDate $dtDate "Day Name" "day_name"

# Attribute relationships for natural hierarchies (unique child -> parent!)
$aYearMonth.AttributeRelationships.Add((New-Object Microsoft.AnalysisServices.AttributeRelationship($aQuarterLbl.ID))) | Out-Null
$aQuarterLbl.AttributeRelationships.Add((New-Object Microsoft.AnalysisServices.AttributeRelationship($aYear.ID))) | Out-Null
$aSeasonLbl.AttributeRelationships.Add((New-Object Microsoft.AnalysisServices.AttributeRelationship($aYear.ID))) | Out-Null
$aDateKey.AttributeRelationships.Add((New-Object Microsoft.AnalysisServices.AttributeRelationship($aYearMonth.ID))) | Out-Null
$aDateKey.AttributeRelationships.Add((New-Object Microsoft.AnalysisServices.AttributeRelationship($aSeasonLbl.ID))) | Out-Null
$aDateKey.AttributeRelationships.Add((New-Object Microsoft.AnalysisServices.AttributeRelationship($aMonthName.ID))) | Out-Null
$aDateKey.AttributeRelationships.Add((New-Object Microsoft.AnalysisServices.AttributeRelationship($aMonthNum.ID))) | Out-Null
$aDateKey.AttributeRelationships.Add((New-Object Microsoft.AnalysisServices.AttributeRelationship($aQuarter.ID))) | Out-Null
$aDateKey.AttributeRelationships.Add((New-Object Microsoft.AnalysisServices.AttributeRelationship($aSeason.ID))) | Out-Null
$aDateKey.AttributeRelationships.Add((New-Object Microsoft.AnalysisServices.AttributeRelationship($aIsWeekend.ID))) | Out-Null
$aDateKey.AttributeRelationships.Add((New-Object Microsoft.AnalysisServices.AttributeRelationship($aDayName.ID))) | Out-Null

Add-Hierarchy $dimDate "Date Hierarchy" @("Year", "Quarter Label", "Year Month", "Date Key") | Out-Null
Add-Hierarchy $dimDate "Season Hierarchy" @("Year", "Season Label", "Date Key") | Out-Null
$db.Dimensions.Add($dimDate) | Out-Null

# 2. Dim Hotel
$dtHotel = $schema.Tables["dw_Dim_Hotel"]
$dimHotel = New-Object Microsoft.AnalysisServices.Dimension("Dim Hotel", "Dim Hotel")
$dimHotel.Source = New-Object Microsoft.AnalysisServices.DataSourceViewBinding($dsv.ID)
$aHotelKey = Add-DimAttribute $dimHotel $dtHotel "Hotel Key" "hotel_key" "hotel_name" $true
$aHotelCode = Add-DimAttribute $dimHotel $dtHotel "Hotel Code" "hotel_code"
$aHotelName = Add-DimAttribute $dimHotel $dtHotel "Hotel Name" "hotel_name"
$aCity = Add-DimAttribute $dimHotel $dtHotel "City" "city"
$aCountryH = Add-DimAttribute $dimHotel $dtHotel "Country" "country"
$aCity.AttributeRelationships.Add((New-Object Microsoft.AnalysisServices.AttributeRelationship($aCountryH.ID))) | Out-Null
$aHotelName.AttributeRelationships.Add((New-Object Microsoft.AnalysisServices.AttributeRelationship($aCity.ID))) | Out-Null
$aHotelKey.AttributeRelationships.Add((New-Object Microsoft.AnalysisServices.AttributeRelationship($aHotelName.ID))) | Out-Null
$aHotelKey.AttributeRelationships.Add((New-Object Microsoft.AnalysisServices.AttributeRelationship($aHotelCode.ID))) | Out-Null
Add-Hierarchy $dimHotel "Hotel Hierarchy" @("Country", "City", "Hotel Name") | Out-Null
$db.Dimensions.Add($dimHotel) | Out-Null

# 3. Dim Country
$dtCountry = $schema.Tables["dw_Dim_Country"]
$dimCountry = New-Object Microsoft.AnalysisServices.Dimension("Dim Country", "Dim Country")
$dimCountry.Source = New-Object Microsoft.AnalysisServices.DataSourceViewBinding($dsv.ID)
$aCountryKey = Add-DimAttribute $dimCountry $dtCountry "Country Key" "country_key" "country_iso3" $true
$aCountryIso = Add-DimAttribute $dimCountry $dtCountry "Country ISO3" "country_iso3"
$aRegion = Add-DimAttribute $dimCountry $dtCountry "Region" "region"
$aCountryIso.AttributeRelationships.Add((New-Object Microsoft.AnalysisServices.AttributeRelationship($aRegion.ID))) | Out-Null
$aCountryKey.AttributeRelationships.Add((New-Object Microsoft.AnalysisServices.AttributeRelationship($aCountryIso.ID))) | Out-Null
Add-Hierarchy $dimCountry "Geography Hierarchy" @("Region", "Country ISO3") | Out-Null
$db.Dimensions.Add($dimCountry) | Out-Null

# 4. Dim Market Segment
$dtSeg = $schema.Tables["dw_Dim_Market_Segment"]
$dimSeg = New-Object Microsoft.AnalysisServices.Dimension("Dim Market Segment", "Dim Market Segment")
$dimSeg.Source = New-Object Microsoft.AnalysisServices.DataSourceViewBinding($dsv.ID)
$aSegKey = Add-DimAttribute $dimSeg $dtSeg "Market Segment Key" "market_segment_key" "market_segment_name" $true
$aSegName = Add-DimAttribute $dimSeg $dtSeg "Market Segment Name" "market_segment_name"
$aSegGrp = Add-DimAttribute $dimSeg $dtSeg "Segment Group" "segment_group"
$aSegName.AttributeRelationships.Add((New-Object Microsoft.AnalysisServices.AttributeRelationship($aSegGrp.ID))) | Out-Null
$aSegKey.AttributeRelationships.Add((New-Object Microsoft.AnalysisServices.AttributeRelationship($aSegName.ID))) | Out-Null
Add-Hierarchy $dimSeg "Market Segment Hierarchy" @("Segment Group", "Market Segment Name") | Out-Null
$db.Dimensions.Add($dimSeg) | Out-Null

# 5. Dim Distribution Channel
$dtCh = $schema.Tables["dw_Dim_Distribution_Channel"]
$dimCh = New-Object Microsoft.AnalysisServices.Dimension("Dim Distribution Channel", "Dim Distribution Channel")
$dimCh.Source = New-Object Microsoft.AnalysisServices.DataSourceViewBinding($dsv.ID)
$aChKey = Add-DimAttribute $dimCh $dtCh "Distribution Channel Key" "distribution_channel_key" "distribution_channel_name" $true
$aChName = Add-DimAttribute $dimCh $dtCh "Distribution Channel Name" "distribution_channel_name"
$aChKey.AttributeRelationships.Add((New-Object Microsoft.AnalysisServices.AttributeRelationship($aChName.ID))) | Out-Null
$db.Dimensions.Add($dimCh) | Out-Null

# 6. Dim Room Type
$dtRoom = $schema.Tables["dw_Dim_Room_Type"]
$dimRoom = New-Object Microsoft.AnalysisServices.Dimension("Dim Room Type", "Dim Room Type")
$dimRoom.Source = New-Object Microsoft.AnalysisServices.DataSourceViewBinding($dsv.ID)
$aRoomKey = Add-DimAttribute $dimRoom $dtRoom "Room Type Key" "room_type_key" "room_type_code" $true
$aRoomCode = Add-DimAttribute $dimRoom $dtRoom "Room Type Code" "room_type_code"
$aRoomKey.AttributeRelationships.Add((New-Object Microsoft.AnalysisServices.AttributeRelationship($aRoomCode.ID))) | Out-Null
$db.Dimensions.Add($dimRoom) | Out-Null

# 7. Dim Booking Profile
$dtProf = $schema.Tables["dw_Dim_Booking_Profile"]
$dimProf = New-Object Microsoft.AnalysisServices.Dimension("Dim Booking Profile", "Dim Booking Profile")
$dimProf.Source = New-Object Microsoft.AnalysisServices.DataSourceViewBinding($dsv.ID)
$aProfKey = Add-DimAttribute $dimProf $dtProf "Booking Profile Key" "booking_profile_key" $null $true
$aCustType = Add-DimAttribute $dimProf $dtProf "Customer Type" "customer_type"
$aDepType = Add-DimAttribute $dimProf $dtProf "Deposit Type" "deposit_type"
$aMealCode = Add-DimAttribute $dimProf $dtProf "Meal Code" "meal_code"
$aMealDesc = Add-DimAttribute $dimProf $dtProf "Meal Description" "meal_description"
$aRepGuest = Add-DimAttribute $dimProf $dtProf "Is Repeated Guest" "is_repeated_guest"
foreach ($a in @($aCustType, $aDepType, $aMealCode, $aMealDesc, $aRepGuest)) {
    $aProfKey.AttributeRelationships.Add((New-Object Microsoft.AnalysisServices.AttributeRelationship($a.ID))) | Out-Null
}
$db.Dimensions.Add($dimProf) | Out-Null

# 8. Dim Reservation Status
$dtStat = $schema.Tables["dw_Dim_Reservation_Status"]
$dimStat = New-Object Microsoft.AnalysisServices.Dimension("Dim Reservation Status", "Dim Reservation Status")
$dimStat.Source = New-Object Microsoft.AnalysisServices.DataSourceViewBinding($dsv.ID)
$aStatKey = Add-DimAttribute $dimStat $dtStat "Reservation Status Key" "reservation_status_key" "reservation_status" $true
$aStatName = Add-DimAttribute $dimStat $dtStat "Reservation Status" "reservation_status"
$aIsCanc = Add-DimAttribute $dimStat $dtStat "Is Canceled" "is_canceled"
$aStatName.AttributeRelationships.Add((New-Object Microsoft.AnalysisServices.AttributeRelationship($aIsCanc.ID))) | Out-Null
$aStatKey.AttributeRelationships.Add((New-Object Microsoft.AnalysisServices.AttributeRelationship($aStatName.ID))) | Out-Null
Add-Hierarchy $dimStat "Status Hierarchy" @("Is Canceled", "Reservation Status") | Out-Null
$db.Dimensions.Add($dimStat) | Out-Null

# 9. Dim Agent Company
$dtAg = $schema.Tables["dw_Dim_Agent_Company"]
$dimAg = New-Object Microsoft.AnalysisServices.Dimension("Dim Agent Company", "Dim Agent Company")
$dimAg.Source = New-Object Microsoft.AnalysisServices.DataSourceViewBinding($dsv.ID)
$aAgKey = Add-DimAttribute $dimAg $dtAg "Agent Company Key" "agent_company_key" $null $true
$aAgId = Add-DimAttribute $dimAg $dtAg "Agent ID" "agent_id"
$aCoId = Add-DimAttribute $dimAg $dtAg "Company ID" "company_id"
$aHasAg = Add-DimAttribute $dimAg $dtAg "Has Agent Flag" "has_agent_flag"
$aHasCo = Add-DimAttribute $dimAg $dtAg "Has Company Flag" "has_company_flag"
foreach ($a in @($aAgId, $aCoId, $aHasAg, $aHasCo)) {
    $aAgKey.AttributeRelationships.Add((New-Object Microsoft.AnalysisServices.AttributeRelationship($a.ID))) | Out-Null
}
$db.Dimensions.Add($dimAg) | Out-Null

# ------------------------------------------------------------------------------
# Build Cube: Hotel Booking Cube
# ------------------------------------------------------------------------------
Write-Host "[5/6] Creating Cube 'Hotel Booking Cube' with 2 Measure Groups & MDX Calculations ..."
$cube = New-Object Microsoft.AnalysisServices.Cube("Hotel Booking Cube", "Hotel Booking Cube")
$cube.Source = New-Object Microsoft.AnalysisServices.DataSourceViewBinding($dsv.ID)

# Add Cube Dimensions (including Role-Playing Dimensions)
function Add-CubeDim([string]$dimId, [string]$cubeDimName) {
    $cd = $cube.Dimensions.Add($dimId, $cubeDimName, $cubeDimName)
    return $cd
}

$cdArrivalDate = Add-CubeDim $dimDate.ID "Arrival Date"
$cdBookingDate = Add-CubeDim $dimDate.ID "Booking Date"
$cdStatusDate  = Add-CubeDim $dimDate.ID "Status Date"
$cdStayDate    = Add-CubeDim $dimDate.ID "Stay Date"
$cdHotel       = Add-CubeDim $dimHotel.ID "Dim Hotel"
$cdCountry     = Add-CubeDim $dimCountry.ID "Dim Country"
$cdSegment     = Add-CubeDim $dimSeg.ID "Dim Market Segment"
$cdChannel     = Add-CubeDim $dimCh.ID "Dim Distribution Channel"
$cdResRoom     = Add-CubeDim $dimRoom.ID "Reserved Room Type"
$cdAssRoom     = Add-CubeDim $dimRoom.ID "Assigned Room Type"
$cdProfile     = Add-CubeDim $dimProf.ID "Dim Booking Profile"
$cdStatus      = Add-CubeDim $dimStat.ID "Dim Reservation Status"
$cdAgent       = Add-CubeDim $dimAg.ID "Dim Agent Company"

# Helper to add Regular MeasureGroupDimension link
function Link-DimToMG(
    [Microsoft.AnalysisServices.MeasureGroup]$mg,
    [Microsoft.AnalysisServices.CubeDimension]$cubeDim,
    [string]$granularityAttrId,
    [System.Data.DataTable]$factDt,
    [string]$fkCol
) {
    $mgd = New-Object Microsoft.AnalysisServices.RegularMeasureGroupDimension($cubeDim.ID)
    $mga = New-Object Microsoft.AnalysisServices.MeasureGroupAttribute($granularityAttrId)
    $mga.Type = [Microsoft.AnalysisServices.MeasureGroupAttributeType]::Granularity
    $mga.KeyColumns.Add((New-DataItem $factDt $fkCol)) | Out-Null
    $mgd.Attributes.Add($mga) | Out-Null
    $mg.Dimensions.Add($mgd) | Out-Null
}

function Add-Measure(
    [Microsoft.AnalysisServices.MeasureGroup]$mg,
    [System.Data.DataTable]$factDt,
    [string]$mName,
    [string]$colName,
    [Microsoft.AnalysisServices.AggregationFunction]$aggFunc = [Microsoft.AnalysisServices.AggregationFunction]::Sum,
    [string]$fmt = "#,##0"
) {
    $m = New-Object Microsoft.AnalysisServices.Measure($mName, $mName)
    $m.AggregateFunction = $aggFunc
    $m.FormatString = $fmt
    if ($aggFunc -eq [Microsoft.AnalysisServices.AggregationFunction]::Count) {
        $di = New-Object Microsoft.AnalysisServices.DataItem($factDt.TableName, $null, [System.Data.OleDb.OleDbType]::Integer)
        $di.Source = New-Object Microsoft.AnalysisServices.RowBinding($factDt.TableName)
        $m.Source = $di
    } else {
        $m.Source = New-DataItem $factDt $colName
    }
    $mg.Measures.Add($m) | Out-Null
    return $m
}

# --- Measure Group 1: Fact Hotel Booking ---
$mgBooking = New-Object Microsoft.AnalysisServices.MeasureGroup("Fact Hotel Booking", "Fact Hotel Booking")
Add-Measure $mgBooking $dtFact "Total Bookings" $null ([Microsoft.AnalysisServices.AggregationFunction]::Count) "#,##0" | Out-Null
Add-Measure $mgBooking $dtFact "Actual Revenue" "actual_revenue" ([Microsoft.AnalysisServices.AggregationFunction]::Sum) "€#,##0.00" | Out-Null
Add-Measure $mgBooking $dtFact "Estimated Revenue" "estimated_revenue" ([Microsoft.AnalysisServices.AggregationFunction]::Sum) "€#,##0.00" | Out-Null
Add-Measure $mgBooking $dtFact "Lost Revenue" "lost_revenue" ([Microsoft.AnalysisServices.AggregationFunction]::Sum) "€#,##0.00" | Out-Null
Add-Measure $mgBooking $dtFact "Total Nights" "total_nights" ([Microsoft.AnalysisServices.AggregationFunction]::Sum) "#,##0" | Out-Null
Add-Measure $mgBooking $dtFact "Weekend Nights" "stays_in_weekend_nights" ([Microsoft.AnalysisServices.AggregationFunction]::Sum) "#,##0" | Out-Null
Add-Measure $mgBooking $dtFact "Week Nights" "stays_in_week_nights" ([Microsoft.AnalysisServices.AggregationFunction]::Sum) "#,##0" | Out-Null
Add-Measure $mgBooking $dtFact "Total Guests" "total_guests" ([Microsoft.AnalysisServices.AggregationFunction]::Sum) "#,##0" | Out-Null
Add-Measure $mgBooking $dtFact "Lead Time Sum" "lead_time" ([Microsoft.AnalysisServices.AggregationFunction]::Sum) "#,##0" | Out-Null
Add-Measure $mgBooking $dtFact "ADR Sum" "adr" ([Microsoft.AnalysisServices.AggregationFunction]::Sum) "€#,##0.00" | Out-Null
Add-Measure $mgBooking $dtFact "Special Requests" "total_of_special_requests" ([Microsoft.AnalysisServices.AggregationFunction]::Sum) "#,##0" | Out-Null
Add-Measure $mgBooking $dtFact "Booking Changes" "booking_changes" ([Microsoft.AnalysisServices.AggregationFunction]::Sum) "#,##0" | Out-Null
Add-Measure $mgBooking $dtFact "Room Changed Count" "RoomChangedCount" ([Microsoft.AnalysisServices.AggregationFunction]::Sum) "#,##0" | Out-Null

$pBooking = New-Object Microsoft.AnalysisServices.Partition("Fact_Hotel_Booking_Partition", "Fact_Hotel_Booking_Partition")
$pBooking.Source = New-Object Microsoft.AnalysisServices.DsvTableBinding($dsv.ID, "dw_Fact_Hotel_Booking")
$pBooking.StorageMode = [Microsoft.AnalysisServices.StorageMode]::Molap
$mgBooking.Partitions.Add($pBooking) | Out-Null

Link-DimToMG $mgBooking $cdArrivalDate $aDateKey.ID $dtFact "arrival_date_key"
Link-DimToMG $mgBooking $cdBookingDate $aDateKey.ID $dtFact "booking_date_key"
Link-DimToMG $mgBooking $cdStatusDate  $aDateKey.ID $dtFact "status_date_key"
Link-DimToMG $mgBooking $cdHotel       $aHotelKey.ID $dtFact "hotel_key"
Link-DimToMG $mgBooking $cdCountry     $aCountryKey.ID $dtFact "country_key"
Link-DimToMG $mgBooking $cdSegment     $aSegKey.ID $dtFact "market_segment_key"
Link-DimToMG $mgBooking $cdChannel     $aChKey.ID $dtFact "distribution_channel_key"
Link-DimToMG $mgBooking $cdResRoom     $aRoomKey.ID $dtFact "reserved_room_type_key"
Link-DimToMG $mgBooking $cdAssRoom     $aRoomKey.ID $dtFact "assigned_room_type_key"
Link-DimToMG $mgBooking $cdProfile     $aProfKey.ID $dtFact "booking_profile_key"
Link-DimToMG $mgBooking $cdStatus      $aStatKey.ID $dtFact "reservation_status_key"
Link-DimToMG $mgBooking $cdAgent       $aAgKey.ID $dtFact "agent_company_key"

$cube.MeasureGroups.Add($mgBooking) | Out-Null

# --- Measure Group 2: Fact Daily Stay Snapshot ---
$dtDaily = $schema.Tables["dw_Fact_Daily_Stay_Snapshot"]
$mgDaily = New-Object Microsoft.AnalysisServices.MeasureGroup("Fact Daily Stay Snapshot", "Fact Daily Stay Snapshot")
Add-Measure $mgDaily $dtDaily "Daily Room Nights Occupied" "night_count" ([Microsoft.AnalysisServices.AggregationFunction]::Sum) "#,##0" | Out-Null
Add-Measure $mgDaily $dtDaily "Daily Allocated Revenue" "daily_revenue" ([Microsoft.AnalysisServices.AggregationFunction]::Sum) "€#,##0.00" | Out-Null

$pDaily = New-Object Microsoft.AnalysisServices.Partition("Fact_Daily_Stay_Partition", "Fact_Daily_Stay_Partition")
$pDaily.Source = New-Object Microsoft.AnalysisServices.DsvTableBinding($dsv.ID, "dw_Fact_Daily_Stay_Snapshot")
$pDaily.StorageMode = [Microsoft.AnalysisServices.StorageMode]::Molap
$mgDaily.Partitions.Add($pDaily) | Out-Null

Link-DimToMG $mgDaily $cdStayDate $aDateKey.ID $dtDaily "stay_date_key"
Link-DimToMG $mgDaily $cdHotel    $aHotelKey.ID $dtDaily "hotel_key"
Link-DimToMG $mgDaily $cdAssRoom  $aRoomKey.ID $dtDaily "assigned_room_type_key"
Link-DimToMG $mgDaily $cdSegment  $aSegKey.ID $dtDaily "market_segment_key"
Link-DimToMG $mgDaily $cdProfile  $aProfKey.ID $dtDaily "booking_profile_key"

$cube.MeasureGroups.Add($mgDaily) | Out-Null

# --- MDX Script (Calculated Members inside Cube) ---
$mdxScript = New-Object Microsoft.AnalysisServices.MdxScript("MdxScript", "MdxScript")
$mdxCmd = New-Object Microsoft.AnalysisServices.Command(@"
CALCULATE;

CREATE MEMBER CURRENTCUBE.[Measures].[Canceled Bookings]
 AS ([Measures].[Total Bookings], [Dim Reservation Status].[Is Canceled].&[True]),
FORMAT_STRING = "#,##0",
VISIBLE = 1;

CREATE MEMBER CURRENTCUBE.[Measures].[Completed Bookings]
 AS ([Measures].[Total Bookings], [Dim Reservation Status].[Is Canceled].&[False]),
FORMAT_STRING = "#,##0",
VISIBLE = 1;

CREATE MEMBER CURRENTCUBE.[Measures].[Cancellation Rate]
 AS IIF([Measures].[Total Bookings] = 0, NULL, [Measures].[Canceled Bookings] / [Measures].[Total Bookings]),
FORMAT_STRING = "0.00%",
VISIBLE = 1;

CREATE MEMBER CURRENTCUBE.[Measures].[Revenue Loss Ratio]
 AS IIF([Measures].[Estimated Revenue] = 0, NULL, [Measures].[Lost Revenue] / [Measures].[Estimated Revenue]),
FORMAT_STRING = "0.00%",
VISIBLE = 1;

CREATE MEMBER CURRENTCUBE.[Measures].[Avg Lead Time]
 AS IIF([Measures].[Total Bookings] = 0, NULL, [Measures].[Lead Time Sum] / [Measures].[Total Bookings]),
FORMAT_STRING = "#,##0.0",
VISIBLE = 1;

CREATE MEMBER CURRENTCUBE.[Measures].[Room Nights Sold]
 AS ([Measures].[Total Nights], [Dim Reservation Status].[Is Canceled].&[False]),
FORMAT_STRING = "#,##0",
VISIBLE = 1;

CREATE MEMBER CURRENTCUBE.[Measures].[Weighted ADR]
 AS IIF([Measures].[Room Nights Sold] = 0, NULL, [Measures].[Actual Revenue] / [Measures].[Room Nights Sold]),
FORMAT_STRING = "€#,##0.00",
VISIBLE = 1;

CREATE MEMBER CURRENTCUBE.[Measures].[Room Change Rate]
 AS IIF([Measures].[Total Bookings] = 0, NULL, [Measures].[Room Changed Count] / [Measures].[Total Bookings]),
FORMAT_STRING = "0.00%",
VISIBLE = 1;
"@)
$mdxScript.Commands.Add($mdxCmd) | Out-Null
$cube.MdxScripts.Add($mdxScript) | Out-Null

$db.Cubes.Add($cube) | Out-Null

# ------------------------------------------------------------------------------
# Deploy & Process Full!
# ------------------------------------------------------------------------------
Write-Host "[6/6] Deploying and Processing FULL on $SsasServer (MOLAP storage) ..."
$db.Update([Microsoft.AnalysisServices.UpdateOptions]::ExpandFull)
$db.Process([Microsoft.AnalysisServices.ProcessType]::ProcessFull)

# Export XMLA Create Script for reproducibility & submission
$exportDir = Split-Path -Parent $ExportXmlaPath
if (-not (Test-Path $exportDir)) { New-Item -ItemType Directory -Path $exportDir -Force | Out-Null }
$xmlWriterSettings = New-Object System.Xml.XmlWriterSettings
$xmlWriterSettings.Indent = $true
$xmlWriter = [System.Xml.XmlWriter]::Create($ExportXmlaPath, $xmlWriterSettings)
try {
    $scripter = New-Object Microsoft.AnalysisServices.Scripter
    $scripter.ScriptCreate(@($db), $xmlWriter, $false)
} finally {
    $xmlWriter.Close()
}

Write-Host "[OK] SSAS Multidimensional Database '$OlapDatabase' deployed & processed successfully!"
Write-Host "     Exported XMLA script: $ExportXmlaPath"
$server.Disconnect()
