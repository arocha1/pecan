##' Paramater Data Assimilation using emulator
##'
##' @title Paramater Data Assimilation using emulator
##' @param settings = a pecan settings list
##'
##' @return nothing. Diagnostic plots, MCMC samples, and posterior distributions
##'  are saved as files and db records.
##'
##' @author Mike Dietze
##' @author Ryan Kelly, Istem Fer
##' @export
pda.emulator <- function(settings, params.id=NULL, param.names=NULL, prior.id=NULL, chain=NULL, 
                     iter=NULL, adapt=NULL, adj.min=NULL, ar.target=NULL, jvar=NULL, n.knot=NULL) {
  
  ## this bit of code is useful for defining the variables passed to this function 
  ## if you are debugging
  if(FALSE){
    params.id <- param.names <- prior.id <- chain <- iter <- NULL 
    n.knot <- adapt <- adj.min <- ar.target <- jvar <- NULL
  }

  ## -------------------------------------- Setup ------------------------------------- ##
  ## Handle settings
    settings <- pda.settings(
                  settings=settings, params.id=params.id, param.names=param.names, 
                  prior.id=prior.id, chain=chain, iter=iter, adapt=adapt, 
                  adj.min=adj.min, ar.target=ar.target, jvar=jvar, n.knot=n.knot)
    
    
    extension.check <- settings$assim.batch$extension == "longer"
    
    if(length(extension.check)==0){ # not an extension run
      run.block = TRUE
      path.flag = TRUE
    }else if(length(extension.check)==1 & extension.check == FALSE){ # "round" extension
      run.block = TRUE
      path.flag = FALSE
    }else{ # "longer" extension
      run.block = FALSE
      path.flag = FALSE
    }

   
  ## Open database connection
  if(settings$database$bety$write){
    con <- try(db.open(settings$database$bety), silent=TRUE)
    if(is.character(con)){
      con <- NULL
    }
  } else {
    con <- NULL
  }

  ## Load priors
  temp <- pda.load.priors(settings, con, path.flag)
  prior.list <- temp$prior
  settings <- temp$settings
  pname <-  lapply(prior.list, rownames)
  n.param.all  <- sapply(prior.list, nrow)

  ## Load data to assimilate against
  inputs <- load.pda.data(settings, con)
  n.input <- length(inputs)

  ## Set model-specific functions
  do.call("require",list(paste0("PEcAn.", settings$model$type)))
  my.write.config <- paste("write.config.", settings$model$type,sep="")
  if(!exists(my.write.config)){
    logger.severe(paste(my.write.config,"does not exist. Please make sure that the PEcAn interface is loaded for", settings$model$type))
  }

  ## Select parameters to constrain
  prior.ind <- lapply(seq_along(settings$pfts), 
                      function(x) which(pname[[x]] %in% settings$assim.batch$param.names[[x]]))
  n.param <- sapply(prior.ind, length)

  ## Get the workflow id
  if ("workflow" %in% names(settings)) {
    workflow.id <- settings$workflow$id
  } else {
    workflow.id <- -1
  }

  ## Create an ensemble id
  settings$assim.batch$ensemble.id <- pda.create.ensemble(settings, con, workflow.id)

  ## Set prior distribution functions (d___, q___, r___, and multivariate versions)
  prior.fn <- lapply(prior.list, pda.define.prior.fn)

  ## Set up likelihood functions
  llik.fn <- pda.define.llik.fn(settings)


  ## ------------------------------------ Emulator ------------------------------------ ##
  ## Propose parameter knots (X) for emulator design
  knots.list <- lapply(seq_along(settings$pfts),
                       function(x) pda.generate.knots(settings$assim.batch$n.knot, n.param.all[x], prior.ind[[x]], prior.fn[[x]], pname[[x]]))

  knots.params <- lapply(knots.list, `[[`, "params")
  knots.probs <- lapply(knots.list, `[[`, "probs")

  ## Check which emulator extension type requested if any
  if(!is.null(settings$assim.batch$extension)){
    
    if(settings$assim.batch$extension == "round"){
      
      # save the original prior path
      temp.path = settings$assim.batch$prior$path
      
      # set prior path to NULL to use the previous PDA's posterior densities as new priors this time
      settings$assim.batch$prior$path = NULL
      
      ## Re-load priors
      temp <- pda.load.priors(settings, con) # loads the posterior dist. from previous emulator run
      prior.list <- temp$prior
      settings$assim.batch$prior$path = temp.path
      
      ## Re-set prior distribution functions 
      prior.fn <- lapply(prior.list, pda.define.prior.fn)
      
      ## Propose a percentage of the new parameter knots from the posterior of previous run
      knot.par <- ifelse(!is.null(settings$assim.batch$knot.par),
                         as.numeric(settings$assim.batch$knot.par),
                         0.75)
                         
      n.post.knots <- floor(knot.par * settings$assim.batch$n.knot)
      
      knots.list.temp <- lapply(seq_along(settings$pfts),
                           function(x) pda.generate.knots(n.post.knots, n.param.all[x], prior.ind[[x]], prior.fn[[x]], pname[[x]]))
      knots.params.temp <- lapply(knots.list.temp, `[[`, "params")

      for(i in seq_along(settings$pfts)){
        # mixture of knots 
        knots.list[[i]]$params <- rbind(knots.params[[i]][sample(nrow(knots.params[[i]]), (settings$assim.batch$n.knot - n.post.knots)),], 
                                   knots.list.temp[[i]]$params)
        
      }

      
      # Return to original prior distribution
      temp <- pda.load.priors(settings, con)
      prior.list <- temp$prior
      prior.fn <- lapply(prior.list, pda.define.prior.fn)
      
      
      # Convert parameter values to probabilities according to previous prior distribution
      knots.list$probs <- knots.list$params
      for(pft in seq_along(settings$pfts)){
        for(i in 1:n.param.all[[pft]]) {
          knots.list[[pft]]$probs[,i] <- eval(prior.fn[[pft]]$pprior[[i]], list(q=knots.list[[pft]]$params[,i]))
        }
      }

      knots.params <- lapply(knots.list, `[[`, "params")
      knots.probs <- lapply(knots.list, `[[`, "probs")

    } # end of round-if
  } # end of extension-if
  
  
  if(run.block){
    ## Set up runs and write run configs for all proposed knots 
    run.ids <- pda.init.run(settings, con, my.write.config, workflow.id, knots.params, 
                            n=settings$assim.batch$n.knot, 
                            run.names=paste0(settings$assim.batch$ensemble.id,".knot.",1:settings$assim.batch$n.knot))
    
    ## start model runs
    start.model.runs(settings,settings$database$bety$write)
    
    ## Retrieve model outputs, calculate likelihoods (and store them in database)
    LL.0 <- rep(NA, settings$assim.batch$n.knot)
    model.out <- list()
    
    for(i in 1:settings$assim.batch$n.knot) {
      ## read model outputs
      model.out[[i]] <- pda.get.model.output(settings, run.ids[i], inputs)
      
      ## calculate likelihood
      LL.0[i] <- pda.calc.llik(settings, con, model.out[[i]], run.ids[i], inputs, llik.fn)
    }
  } 
  
  
  ## if it is not specified, default to GPfit
  if(is.null(settings$assim.batch$GPpckg)) settings$assim.batch$GPpckg="GPfit"
  
  if(settings$assim.batch$GPpckg=="GPfit"){ # GPfit-if
    
    if(run.block){ 
      
      ## GPfit optimization routine assumes that inputs are in [0,1]
      ## Instead of drawing from parameters, we draw from probabilities
      knots.probs.all <- do.call("cbind", knots.probs)
      prior.ind.all <- which(unlist(pname) %in% unlist(settings$assim.batch$param.names))
        
      X <- knots.probs.all[, prior.ind.all, drop=FALSE]
      
      LL.X <- cbind(X, LL.0)
      
      if(!is.null(settings$assim.batch$extension)){ 
        # check whether another "round" of emulator requested
        
        # load original knots
        load(settings$assim.batch$llik.path)
        LL <- rbind(LL.X, LL)
        
      }else{ 
        LL <- LL.X
      }
      
      logger.info(paste0("Using 'GPfit' package for Gaussian Process Model fitting."))
      require(GPfit)
      ## Generate emulator on LL-probs
      GPmodel <- GP_fit(X = LL[,-ncol(LL), drop=FALSE],
                        Y = LL[,ncol(LL), drop=FALSE])
      gp=GPmodel
      
    }else{
      load(settings$assim.batch$emulator.path) # load previously built emulator to run a longer mcmc
      load(settings$assim.batch$llik.path)
      load(settings$assim.batch$jvar.path)
      load(settings$assim.batch$mcmc.path)
      
      init.list <- list()
      
      for(c in 1:settings$assim.batch$chain){
        init.x <- mcmc.list[[c]][nrow(mcmc.list[[c]]),]
        
        prior.all <- do.call("rbind", prior.list)
        prior.ind.all <- which(unlist(pname) %in% unlist(settings$assim.batch$param.names))
        prior.fn.all <- pda.define.prior.fn(prior.all)
        
        init.list[[c]] <-  as.list(sapply(seq_along(prior.ind.all), 
                                          function(x) eval(prior.fn.all$pprior[[prior.ind.all[x]]], list(q=init.x[x]))))
      }
    }
    
    ## Change the priors to unif(0,1) for mcmc.GP
    prior.all <- do.call("rbind", prior.list)
    
    prior.all[prior.ind.all,]=rep(c("unif",0,1,"NA"),each=sum(n.param))
    ## Set up prior functions accordingly
    prior.fn.all <- pda.define.prior.fn(prior.all)
    pckg=1
    
  }else{  # GPfit-else
    
    if(run.block){
      X <- data.frame(knots.params[, prior.ind])
      names(X) <- pname[prior.ind]
      
      LL.X <- data.frame(LLik = LL.0, X)
      
      if(!is.null(settings$assim.batch$extension)){ 
        # check whether another "round" of emulator requested
        
        # load original knots
        load(settings$assim.batch$llik.path)
        LL <- rbind(LL.X, LL)
        
      }else{ 
        LL <- LL.X
      }
      
      
      logger.info(paste0("Using 'kernlab' package for Gaussian Process Model fitting."))
      require(kernlab)
      ## Generate emulator on LL-params
      kernlab.gp <- gausspr(LLik~., data=LL)
      gp=kernlab.gp
      
    }else{
      load(settings$assim.batch$emulator.path)
    }
    
    pckg=2
  }
  
  # define range to make sure mcmc.GP doesn't propose new values outside 
  
  rng <- matrix(c(sapply(prior.fn.all$qprior[prior.ind.all] ,eval,list(p=0)),
                  sapply(prior.fn.all$qprior[prior.ind.all] ,eval,list(p=1))),
                nrow=sum(n.param))
  
  
  
  if(run.block){
    
    jvar.list <- list() 
    init.list <- list()
    
    for(c in 1:settings$assim.batch$chain){
      jvar.list[[c]]  <- sapply(prior.fn.all$qprior, 
                                function(x) 0.1 * diff(eval(x, list(p=c(0.05,0.95)))))[prior.ind.all]
      
      init.x <- lapply(prior.ind.all, function(v) eval(prior.fn.all$rprior[[v]], list(n=1)))
      names(init.x) <- unlist(pname)[prior.ind.all]
      init.list[[c]] <- init.x
    }
  }
  
  
  
  if(!is.null(settings$assim.batch$mix)){
    mix <- settings$assim.batch$mix
  }else if(sum(n.param) > 1){
    mix <- "joint"
  }else{
    mix <- "each"
  } 
  

  ## Sample posterior from emulator
  mcmc.out <- lapply(1:settings$assim.batch$chain, function(chain){
    mcmc.GP(gp        = gp, ## Emulator
            pckg      = pckg, ## flag to determine which predict method to use
            x0        = init.list[[chain]],     ## Initial conditions
            nmcmc     = settings$assim.batch$iter,       ## Number of reps
            rng       = rng,       ## range
            format    = "lin",      ## "lin"ear vs "log" of LogLikelihood 
            mix       = mix,     ## Jump "each" dimension independently or update them "joint"ly
            #                  jmp0 = apply(X,2,function(x) 0.3*diff(range(x))), ## Initial jump size
            jmp0      = sqrt(jvar.list[[chain]]),  ## Initial jump size
            ar.target = settings$assim.batch$jump$ar.target,   ## Target acceptance rate
            priors    = prior.fn.all$dprior[prior.ind.all], ## priors
            settings  = settings
    )})
  
  mcmc.list.tmp <- list()
  
  for(c in 1:settings$assim.batch$chain) {
    
    m <- mcmc.out[[c]]$mcmc
    
    
    if(settings$assim.batch$GPpckg=="GPfit"){
      ## Set the prior functions back to work with actual parameter range

      prior.all <- do.call("rbind", prior.list)
      prior.fn.all <- pda.define.prior.fn(prior.all)
     
      ## Convert probabilities back to parameter values
      for(i in 1:sum(n.param)) {
        m[,i] <- eval(prior.fn.all$qprior[prior.ind.all][[i]], list(p=mcmc.out[[c]]$mcmc[,i]))
      }
    }
    colnames(m) <- unlist(pname)[prior.ind.all]
    mcmc.list.tmp[[c]] <- m
    
    jvar.list[[c]] <- mcmc.out[[c]]$jump@history[nrow(mcmc.out[[c]]$jump@history),]
  }
  
  
  if(length(extension.check)==1 & !run.block){
    
    # merge with previous run's mcmc samples
    mcmc.list <- mapply(rbind, mcmc.list, mcmc.list.tmp, SIMPLIFY=FALSE)
    settings$assim.batch$iter <- nrow(mcmc.list[[1]])
    
  }else{
    
    mcmc.list <- mcmc.list.tmp

  }
  
  if(FALSE) {
    gp = kernlab.gp; x0 = init.x; nmcmc = settings$assim.batch$iter; rng= NULL; format = "lin"
    mix = "each"; jmp0 = apply(X,2,function(x) 0.3*diff(range(x)))
    jmp0 = sqrt(unlist(settings$assim.batch$jump$jvar)); ar.target = settings$assim.batch$jump$ar.target
    priors = prior.fn$dprior[prior.ind]
  }


  ## ------------------------------------ Clean up ------------------------------------ ##
  ## Save emulator, outputs files
  settings$assim.batch$emulator.path <- file.path(settings$outdir, 
                                                  paste0('emulator.pda', settings$assim.batch$ensemble.id, '.Rdata'))
  save(gp, file = settings$assim.batch$emulator.path)
  
  
  settings$assim.batch$llik.path <- file.path(settings$outdir, 
                                              paste0('llik.pda', settings$assim.batch$ensemble.id, '.Rdata'))
  save(LL, file = settings$assim.batch$llik.path)
  
  
  settings$assim.batch$mcmc.path <- file.path(settings$outdir, 
                                              paste0('mcmc.list.pda', settings$assim.batch$ensemble.id, '.Rdata'))
  save(mcmc.list, file = settings$assim.batch$mcmc.path)
  
  settings$assim.batch$jvar.path <- file.path(settings$outdir, 
                                              paste0('jvar.pda', settings$assim.batch$ensemble.id, '.Rdata'))
  save(jvar.list, file = settings$assim.batch$jvar.path)
  
  
  # Separate each PFT's parameter samples to their own list
  mcmc.param.list <- list()
  ind <- 0
  for(i in seq_along(settings$pfts)){
    mcmc.param.list[[i]] <-  lapply(mcmc.list, function(x) x[, (ind+1):(ind + n.param[i]), drop=FALSE])
    ind <- ind + n.param[i]
  }


  settings <- pda.postprocess(settings, con, mcmc.param.list, jvar.list, pname, prior.list, prior.ind)

  ## close database connection
  if(!is.null(con)) db.close(con)

  ## Output an updated settings list
  return(settings)
  
} ## end pda.emulator
