#' ConvertSpreadsheetToNcdf.R
#'
#' Converts data from a PALS formatted spreadhseet to
#' netcdf.
#'
#' author: Anna Ukkola UNSW 2017

#' Main function to convert Fluxnet2015 CSV-files to NetCDF
#'
#' @param infile input filename,
#'   e.g. "FULLSET/FLX_AU-How_FLUXNET2015_FULLSET_HH_2001-2014_1-3.csv"
#' @param era_file ERA input file (needed if using ERAinterim to gapfill met variables)
#'   e.g. "FULLSET/FLX_AU-How_FLUXNET2015_ERAI_HH_1989-2014_1-3.csv"
#' @param threshold How many percent of time steps allowed to be missing in any given year?
#' @param min_yrs Minimum number of consecutive years to process
#' @param out_path output path e.g. "./FLUXNET2016_processing/"
#' @param site_code Fluxnet site code e.g. "AU-How"
#' @param ERA_gapfill Gapfill met variables using ERAinterim?
#' @param plot Should annual, diurnal and/or 14-day running mean plots be produced? Set to NA if not
#' 
#' @export
#'
#'
convert_fluxnet_to_netcdf <- function(infile, site_code, out_path,
                                      ERA_file=NA, ERA_gapfill=FALSE,
                                      datasetname="FLUXNET2015", datasetversion="v1-3",
                                      missing = 10, gapfill_all=10,
                                      gapfill_good=NA, gapfill_med=NA,
                                      gapfill_poor=NA, min_yrs=2,
                                      plot=c("annual", "diurnal", "timeseries")) {
    
    library(R.utils)
    library(pals)
  
    
    
    ## Create sub-folders for outputs ##
    
    #NetCDF files
    outpath_nc <- paste(out_path, "/Nc_files", sep="")
    dir.create(outpath_nc, showWarnings = FALSE, recursive=TRUE)
    
    #Plots (if code set to plot)
    if(!any(is.na(plot))){
      outpath_plot <- paste(out_path, "/Figures", sep="")
      dir.create(outpath_plot, showWarnings = FALSE, recursive=TRUE)
    }

    
    ################################
    ###--- Read variable data ---###
    ################################
    
    #File contains desired variables (refer to Fluxnet2015 documentation for full variable descriptions;
    #http://fluxnet.fluxdata.org/data/fluxnet2015-dataset/fullset-data-product/)
    
    #Find variable file path (not using data() command directly because reads a CSV with a
    #semicolon separator and this leads to incorrect table headers)
    var_file <- system.file("data","Output_variables.csv",package="FluxnetProcessing")
    
    vars <- read.csv(var_file, header=TRUE,
    colClasses=c("character", "character", "character",
                 "character", "character", "character",
                 "character",
                 "numeric",   "numeric",
                 "logical", "logical",
                 "character"))
    
    
    #Name of time stamp variables
    time_vars <- c("TIMESTAMP_START", "TIMESTAMP_END")
    
    
    #Read site information (lon, lat, elevation)
    site_info <- get_site_metadata(site_code)
    
    #Should site be excluded? If so, abort and print reason.
    #This option is set in the site info file (inside data folder)
    #Mainly excludes sites with mean annual ET excluding P, implying
    #irrigation or other additional water source.
    if(site_info$Exclude){
        CheckError(paste("Site not processed. Reason:", site_info$Exclude_reason,
                         ". This is set in site info file, change >Exclude< options",
                         "in the file to process site"))
    }
    
    
    # Read text file containing flux data:
    DataFromText <- ReadTextFluxData(fileinname=infile, vars=vars,
                                     time_vars=time_vars)
    
    
    # Make sure whole number of days in dataset:
    CheckSpreadsheetTiming(DataFromText)
    
    
    # Check if variables have gaps in the time series and determine what years to output:
    gaps  <- CheckDataGaps(datain = DataFromText, missing_val = SprdMissingVal,
                           QCmeasured=QCmeasured, QCgapfilled=QCgapfilled,
                           missing = missing, gapfill_all=gapfill_all,
                           gapfill_good=gapfill_good, gapfill_med=gapfill_med,
                           gapfill_poor=gapfill_poor, min_yrs=min_yrs,
                           essential_met = vars$Output_variable[which(vars$Essential_met)],
                           preferred_eval = vars$Output_variable[which(vars$Preferred_eval)])
    
    
    #Remove evaluation variables that have too many gaps    COMPLETE !!!!!!
    
    
    #Add an option for this
    
    
    
    
    
    
    ##############################################
    ###--- Gapfill meteorological variables ---###
    ##############################################
    
    # gapfill using ERA-interim data provided as part of FLUXNET2015
    if(ERA_gapfill){
        
        era_data <- read.csv(ERA_file, header=TRUE, colClasses=c("character", "character",
        rep("numeric", 7)))
        
        #ERAinterim data provided for 1989-2014, need to extract common years with flux obs
        #Find start and end
        obs_start <- DataFromText$time$TIMESTAMP_START
        start_era <- which(era_data$TIMESTAMP_START == obs_start[1])
        end_era   <- which(era_data$TIMESTAMP_START == obs_start[length(obs_start)])
        
        #Extract correct time steps
        era_data  <- era_data[start_era:end_era,]
        
        #Find indices for met variables to be gapfilled
        ind <- which(DataFromText$categories=="Met")
        
        #Retrieve VPD and air temp units. Used to convert ERAinterim VPD to RH in gapfill function
        tair_units <- DataFromText$units$original_units[which(DataFromText$vars=="Tair")]
        vpd_units  <- DataFromText$units$original_units[which(DataFromText$vars=="VPD")]
        
        #Gapfill met variables
        temp_data <- GapfillMet(datain=DataFromText$data[,ind], era_data=era_data,
        era_vars=DataFromText$era_vars[ind],
        tair_units=tair_units, vpd_units=vpd_units,
        missing_val=SprdMissingVal)
        
        
        #Check that column names of temp_data and data to be replaced match. Stop if not
        if(!all(colnames(temp_data)==colnames(DataFromText$data[,ind]))){
            CheckError(paste("Error gap-filling met data with ERAinterim.", 
                             "Column names of data to be replaced do not match"))
        }
        
        
        #Replace original met variables with gap-filled variables
        DataFromText$data[,ind] <- temp_data$datain
        
        
        #If new QC variables were created, create and append
        #variable attributes to data frame
        if(length(temp_data$new_qc) > 0){
            
                    
            #Append qc time series to data
            DataFromText$data <- cbind(DataFromText$data, temp_data$new_qc)
            
            qc_vars <- colnames(temp_data$new_qc)
            
            for(k in 1:length(qc_vars)){
                DataFromText <- create_qc_var(DataFromText, qc_name=qc_vars[k])
            }
        }
        
        
        #Sanity check
        if(!all(colnames(DataFromText$data)==DataFromText$vars)){
          CheckError("Error creating new QC flags")
        }
    }
    
    
    
    # Convert data units from original Fluxnet units
    # to desired units as set in variables.csv
    ConvertedData <- ChangeUnits(DataFromText)
    
    
    # Check that data are within acceptable ranges: 
    CheckTextDataRanges(ConvertedData, missingval=NcMissingVal)
    
    
    #Replace original data with converted data
    DataFromText <- ConvertedData
    
    
    #Determine number of files to be written (split site according to data gaps if necessary)
    no_files <- length(unique(gaps$consec))
    
    
    
    
    #write github revision number in netcdf attributes
    
    ####################################################
    ###--- Write output met and flux NetCDF files ---###
    ####################################################
    
    for(k in 1:no_files){
        
        
        #Find start year, day and hour
        nc_starttime <- findStartTime(start = strptime(DataFromText$time[gaps$tseries_start[k],1], "%Y%m%d%H%M"))
        
        
        #Extract start and end years
        start_yr <- substring(DataFromText$time[gaps$tseries_start[k],1], 1, 4)
        end_yr   <- substring(DataFromText$time[gaps$tseries_end[k],1], 1, 4)
        
        
        #Create output file names
        #If only one year, only write start year, else write time period
        if(start_yr==end_yr){
            metfilename  <- paste(outpath_nc, "/", site_code, "_", start_yr, 
                                  "_", datasetname, "_Met.nc", sep="")
            fluxfilename <- paste(outpath_nc, "/", site_code, "_", start_yr, 
                                  "_", datasetname, "_Flux.nc", sep="")
            
        } else {
            metfilename  <- paste(outpath_nc, "/", site_code, "_", start_yr, 
                                  "-", end_yr, "_", datasetname, "_Met.nc", sep="")
            fluxfilename <- paste(outpath_nc, "/", site_code, "_", start_yr, 
                                  "-", end_yr, "_", datasetname, "_Flux.nc", sep="")
            
        }
        
        
        ### Create netcdf met driving file ###
        CreateMetNcFile( metfilename=metfilename, 
                         datain=DataFromText,
                         latitude=site_info$SiteLatitude,
                         longitude=site_info$SiteLongitude,
                         site_code=site_code,
                         long_sitename=site_info$Fullname,
                         datasetversion=datasetversion,
                         github_rev=site_info$Processing$git_rev,
                         tier=site_info$Tier,
                         ind_start=gaps$tseries_start[k],
                         ind_end=gaps$tseries_end[k],
                         starttime=nc_starttime,
                         timestepsize=DataFromText$timestepsize,
                         elevation=site_info$SiteElevation,
                         towerheight=site_info$TowerHeight,
                         canopyheight=site_info$CanopyHeight,
                         short_veg_type=site_info$IGBP_vegetation_short,
                         long_veg_type=site_info$IGBP_vegetation_long)
        
        
        
        ### Create netcdf flux data file ###
        CreateFluxNcFile(fluxfilename=fluxfilename, datain=DataFromText,
                         latitude=site_info$SiteLatitude,
                         longitude=site_info$SiteLongitude,
                         site_code=site_code,
                         long_sitename=site_info$Fullname,
                         datasetversion=datasetversion,
                         github_rev=site_info$Processing$git_rev,
                         tier=site_info$Tier,
                         ind_start=gaps$tseries_start[k],
                         ind_end=gaps$tseries_end[k],
                         starttime=nc_starttime,
                         timestepsize=DataFromText$timestepsize,
                         elevation=site_info$SiteElevation,
                         towerheight=site_info$TowerHeight,
                         canopyheight=site_info$CanopyHeight,
                         short_veg_type=site_info$IGBP_vegetation_short,
                         long_veg_type=site_info$IGBP_vegetation_long)
        
        
    }
    
    
    
    
    
    #################################
    ### Plotting analysis outputs ###
    ################################# 
    
    #Plots annual and diurnal cycle plots, as well
    #as a 14-day running mean time series depending on
    #analysis choices (separate figures for Met and Flux vars)
        
    if(!any(is.na(plot))){
      
      #Open met and flux NetCDF file handles
      nc_met <- nc_open(metfilename)
      nc_flux <- nc_open(fluxfilename)
      
      #Initialise output file names (completed in plotting code)
      outfile_met  <- paste(outpath_plot, "/", site_code, "_plot_Met_", sep="")
      outfile_flux <- paste(outpath_plot, "/", site_code, "_plot_Flux_", sep="")
      
   
      ## Plotting ##
      if(any(plot=="annual") | any(plot=="diurnal") | any(plot=="timeseries")){
                
        plot_nc(ncfile=nc_met, analysis_type=plot, 
                vars=DataFromText$vars[DataFromText$categories=="Met"],
                outfile=outfile_met)      
        
        
        plot_nc(ncfile=nc_flux, analysis_type=plot,
                vars=DataFromText$vars[DataFromText$categories=="Eval"],
                outfile=outfile_flux)


      #Analysis type doesn't match options, return warning
      } else {
        warning(paste("Could not produce output plots. Analysis type not",
                "recognised, choose all or any of 'annual',", 
                "'diurnal' and 'timeseries'."))
      }
      
      
      #Close file handles
      nc_close(nc_met)
      nc_close(nc_flux)  
      
    } #plotting
    
    
    
    
    
    
    
} #function
