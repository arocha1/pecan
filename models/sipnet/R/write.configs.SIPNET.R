#--------------------------------------------------------------------------------------------------#
# Template for functions to prepare and write out files model-specific configuration files for MA
#--------------------------------------------------------------------------------------------------#


#--------------------------------------------------------------------------------------------------#
##' Writes a configuration files for your model
#--------------------------------------------------------------------------------------------------#
write.config.SIPNET <- function(defaults, trait.values, settings, outdir, run.id){

  my.outdir = paste(outdir,"/",run.id,"/",sep="") 
  dir.create(my.outdir)
  
  ### WRITE sipnet.in
  template.in <- system.file("sipnet.in", package="PEcAn.SIPNET")
  config.text <- readLines(con=template.in, n=-1)
  config.text <- gsub('@FILENAME@', paste(my.outdir,run.id,sep=""), config.text)
  config.file.name <- paste(run.id,"/sipnet.in", sep='')
  writeLines(config.text, con = paste(outdir,"/", config.file.name, sep=''))
    
  ### Display info to the console.
  print(run.id)

  ### WRITE *.clim
  template.clim <- settings$run$site$met.data.header
  system(paste("cp ",template.clim," ",my.outdir,run.id,".clim",sep=""))
  ### **** WE SHOULD SET THIS UP AS A LINK, RATHER THAN AS A COPY ****
  
  ### WRITE *.param-spatial
  template.paramSpatial <- system.file("template.param-spatial",package="PEcAn.SIPNET")
  system(paste("cp ",template.paramSpatial," ",my.outdir,run.id,".param-spatial",sep=""))
  
  ### WRITE *.param
  template.param <- system.file("template.param",package="PEcAn.SIPNET")
  if("default.param" %in% names(settings$model)){template.param <- settings$model$default.param}

  param <- read.table(template.param)

#### write INITAL CONDITIONS here ####

  ##plantWoodInit gC/m2
  ##laiInit m2/m2
  ##litterInit gC/m2
  ##soilInit gC/m2
  ##litterWFracInit fraction
  ##soilWFracInit fraction
  ##snowInit cm water equivalent
  ##microbeInit mgC/g soil

  
#### write run-specific environmental parameters here ####
  env.traits <- which(names(trait.values) %in% 'env')
  env.traits <- trait.values[[env.traits]]
  env.names <- names(env.traits)


  if("turn_over_time" %in% env.names){
    id = which(param[,1] == 'litterBreakdownRate')
    param[id,2] = env.traits[which(env.names == 'turn_over_time')]
  }
  
  #### write run-specific PFT parameters here ####
  pft.traits <- which(!(names(trait.values) %in% 'env'))[1]
  pft.traits <- trait.values[[pft.traits]]
  pft.names  <- names(pft.traits)

  leafC = 0.5
  if("leafC" %in% pft.names){
    leafC = pft.traits[which(pft.names) == 'leafC']
  }

  SLA = NA
  id = which(param[,1] == 'leafCSpWt')
  if("SLA" %in% pft.names){
    SLA = pft.traits[which(pft.names == 'SLA')]
    param[id,2] = 1000*leafC/SLA
  } else {
    SLA = 1000*leafC/param[id,2]
  }

  Amax = NA
  id = which(param[,1] == 'aMax')
  if("Amax" %in% pft.names){
    Amax = pft.traits[which(pft.names == 'Amax')]
    param[id,2] = Amax*SLA
  } else {
    Amax = param[id,2]*SLA
  }

  if("leaf_respiration_rate_m2" %in% pft.names){
    Rd = pft.traits[which(pft.names == 'leaf_respiration_rate_m2')]
    id = which(param[,1] == 'baseFolRespFrac')
    param[id,2] = max(min(Rd/Amax,1),0)
  }

  if("Vm_low_temp" %in% pft.names){
    param[which(param[,1] == 'psnTMin'),2] = pft.traits[which(pft.names == 'Vm_low_temp')]
  }

  if("growth_resp_factor" %in% pft.names){
    param[which(param[,1] == 'growthRespFrac'),2] =
      pft.traits[which(pft.names == 'growth_resp_factor')]
  }

  Jmax = NA
  if("Jmax" %in% pft.names){
    Jmax = pft.traits[which(pft.names == 'Jmax')]
  }

  alpha = NA
  if("quantum_efficiency" %in% pft.names){
    alpha = pft.traits[which(pft.names == 'quantum_efficiency')]
  }

  if(!is.na(Jmax) & !is.na(alpha)){
    param[which(param[,1] == "halfSatPar"),2] = Jmax/(2*alpha)
    ### WARNING: this is a very coarse linear approximation and needs improvement *****
  }

  if("leaf_turnover_rate" %in% pft.names){
    param[which(param[,1] == 'leafTurnoverRate'),2] =
      pft.traits[which(pft.names == 'leaf_turnover_rate')]
  }

  if("stem_respiration_rate" %in% pft.names){
    vegRespQ10 = param[which(param[,1] == "vegRespQ10"),2]
    id = which(param[,1] == 'baseVegResp')
    ## use Q10 to convert stem resp from reference of 25C to 0C
    param[id,2] = pft.traits[which(pft.names='stem_respiration_rate')]*vegRespQ10^(-25/10)
  }

  if("stomatal_slope.BB" %in% pft.names){
    id = which(param[,1] == 'm_ballBerry')
    param[id,2] = pft.traits[which(pft.names == 'stomatal_slope.BB')]
  }

  if("root_turnover_rate" %in% pft.names){
    id = which(param[,1] == 'fineRootTurnoverRate')
    param[id,2] = pft.traits[which(pft.names == 'root_turnover_rate')]
  }

  if("root_respiration_rate" %in% pft.names){
    fineRootQ10 = param[which(param[,1] == "fineRootQ10"),2]
    id = which(param[,1] == 'baseFineRootResp')
    param[id,2] = pft.traits[which(pft.names=='root_respiration_rate')]*fineRootQ10^(-25/10)
  }
  
  write.table(param,paste(my.outdir,"/",run.id,".param",sep=""),row.names=FALSE,col.names=FALSE,quote=FALSE)
  
  return()

  
  startdate <- as.Date(settings$run$start.date)
  enddate <- as.Date(settings$run$end.date)
  
  #-----------------------------------------------------------------------
  ### Edit a templated config file for runs
  
  config.text <- gsub('@SITE_LAT@', settings$run$site$lat, config.text)
  config.text <- gsub('@SITE_LON@', settings$run$site$lon, config.text)
  config.text <- gsub('@SITE_MET@', settings$run$site$met, config.text)
  config.text <- gsub('@MET_START@', settings$run$site$met.start, config.text)
  config.text <- gsub('@MET_END@', settings$run$site$met.end, config.text)

    #-----------------------------------------------------------------------
    config.text <- gsub('@START_MONTH@', format(startdate, "%m"), config.text)
    config.text <- gsub('@START_DAY@', format(startdate, "%d"), config.text)
    config.text <- gsub('@START_YEAR@', format(startdate, "%Y"), config.text)
    config.text <- gsub('@END_MONTH@', format(enddate, "%m"), config.text)
    config.text <- gsub('@END_DAY@', format(enddate, "%d"), config.text)
    config.text <- gsub('@END_YEAR@', format(enddate, "%Y"), config.text)

    #-----------------------------------------------------------------------
    config.text <- gsub('@OUTDIR@', settings$run$host$outdir, config.text)
    config.text <- gsub('@ENSNAME@', run.id, config.text)

  
    ### Generate a numbered suffix for scratch output folder.  Useful for cleanup.  TEMP CODE. NEED TO UPDATE.
    #cnt = counter(cnt) # generate sequential scratch output directory names 
    #print(cnt)
    #scratch = paste(Sys.getenv("USER"),".",cnt,"/",sep="")
    scratch = Sys.getenv("USER")
    #config.text <- gsub('@SCRATCH@', paste('/scratch/', settings$run$scratch, sep=''), config.text)
    config.text <- gsub('@SCRATCH@', paste('/scratch/', scratch, sep=''), config.text)
    ###
  
    config.text <- gsub('@OUTFILE@', paste('out', run.id, sep=''), config.text)
 
    #-----------------------------------------------------------------------

}
#==================================================================================================#


#--------------------------------------------------------------------------------------------------#
##'
##' @name write.run.generic
##' @title Function to generate generic model run script files
##' @author <unknown>
##' @import PEcAn.utils
#--------------------------------------------------------------------------------------------------#
write.run.generic <- function(settings){
  run.script.template = system.file("data", "run.template.generic", package="PEcAn.generic")
  run.text <- scan(file = run.script.template, 
                   what="character",sep='@', quote=NULL, quiet=TRUE)
  run.text  <- gsub('TMP', paste("/scratch/",Sys.getenv("USER"),sep=""), run.text)
  run.text  <- gsub('BINARY', settings$run$host$ed$binary, run.text)
  run.text <- gsub('OUTDIR', settings$run$host$outdir, run.text)
  runfile <- paste(settings$outdir, 'run', sep='')
  writeLines(run.text, con = runfile)
  if(settings$run$host$name == 'localhost') {
    system(paste('cp ', runfile, settings$run$host$rundir))
  }else{
    system(paste("rsync -outi ", runfile , ' ', settings$run$host$name, ":",
                 settings$run$host$rundir, sep = ''))
  }
}
#==================================================================================================#



####################################################################################################
### EOF.  End of R script file.            	
####################################################################################################