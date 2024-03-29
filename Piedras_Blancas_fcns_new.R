
library(rstan)
library(loo)

get.all.data <- function(sheet.name.inshore, sheet.name.offshore,
                         col.types.inshore, col.types.offshore,
                         col.names.inshore, col.names.offshore,
                         Year, 
                         xls.file.name.inshore, xls.file.name.offshore,
                         start.time, max.shift){
  
  data.inshore <- get.data(Year = Year, 
                           xls.file.name = xls.file.name.inshore, 
                           sheet.name = sheet.name.inshore,
                           col.types = col.types.inshore, 
                           col.names = col.names.inshore, 
                           start.time = start.time,
                           max.shift = max.shift)
  
  data.offshore <- get.data(Year = Year, 
                            xls.file.name = xls.file.name.offshore, 
                            sheet.name = sheet.name.offshore,
                            col.types = col.types.offshore, 
                            col.names = col.names.offshore, 
                            start.time = start.time,
                            max.shift = max.shift)
  
  data.all <- rbind(data.inshore, data.offshore) %>% 
    arrange(Date.date, Minutes_since_0000)
  return(data.all)
}


# col.names has to be in the same order of:
# c("Date", "Event", "Time", "Obs. Code", 
# "Sea State", "Vis. IN", "Cow  / Calf")
# The exact names may be different in each file. Make sure to 
# match them. 

# T0 is the beginning of the first shift (start.time)

get.data <- function(Year, xls.file.name, sheet.name,
                     col.types, col.names, start.time,
                     max.shift){
  
  if (length(col.names) < 8){
    data.out <- read_excel(xls.file.name,
                           sheet = sheet.name,
                           col_types = col.types,
                           col_names = TRUE) %>% 
      dplyr::select(all_of(col.names)) %>%
      transmute(Date = .data[[col.names[[1]]]],
                Event = .data[[col.names[[2]]]],
                Time = .data[[col.names[[3]]]],
                Minutes_since_T0 = sapply(Time, FUN = char_time2min, start.time),
                Minutes_since_0000 = sapply(Time, FUN = char_time2min),
                Shift = sapply(Minutes_since_0000, FUN = find.shift, max.shift = max.shift),
                Obs = .data[[col.names[[4]]]],
                SeaState = .data[[col.names[[5]]]],
                Vis = .data[[col.names[[6]]]],
                Mother_Calf = .data[[col.names[[7]]]],
                Year = Year,
                Area = "off")
     
  } else {
    data.out <- read_excel(xls.file.name,
                           sheet = sheet.name,
                           col_types = col.types,
                           col_names = TRUE) %>% 
      dplyr::select(all_of(col.names)) %>%
      transmute(Date = .data[[col.names[[1]]]],
                Event = .data[[col.names[[2]]]],
                Time = .data[[col.names[[3]]]],
                Minutes_since_T0 = sapply(Time, FUN = char_time2min, start.time),
                Minutes_since_0000 = sapply(Time, FUN = char_time2min),
                Shift = sapply(Minutes_since_0000, FUN = find.shift, max.shift = max.shift),
                Obs = .data[[col.names[[4]]]],
                SeaState = .data[[col.names[[5]]]],
                Vis = .data[[col.names[[6]]]],
                Mother_Calf = .data[[col.names[[7]]]],
                Year = Year,
                Area =  .data[[col.names[[8]]]])
  }
  # Some files contain wrong years...
  years <- year(data.out$Date)
  dif.years <- sum(years - Year, na.rm = T)
  if (dif.years != 0){
    year(data.out$Date) <- Year
  } 

  # filter out rows with NAs in certain fields, then order them using
  # Date and time since T0 (i.e., start.time defined above).
  # Create Date fields with character and date format - may not be necessary?
  data.out %>% 
    filter(!is.na(Date)) %>%
    filter(!is.na(Event)) %>%
    filter(!is.na(Shift)) %>%
    arrange(Date, Minutes_since_0000) %>%
    mutate(Date.date = as.Date(Date),
           Date.char = as.character(Date)) %>%
    dplyr::select(-Date) %>%
    relocate(Date.date) -> data.out
  
  return(data.out)  
}

# extract MCMC diagnostic statistics, including Rhat, loglikelihood, DIC, and LOOIC
MCMC.diag <- function(jm, MCMC.params){
  n.per.chain <- (MCMC.params$n.samples - MCMC.params$n.burnin)/MCMC.params$n.thin
  
  Rhat <- unlist(lapply(jm$Rhat, FUN = max, na.rm = T))
  
  loglik <- jm$sims.list$loglik
  
  Reff <- relative_eff(exp(loglik), 
                       chain_id = rep(1:MCMC.params$n.chains, 
                                      each = n.per.chain),
                       cores = MCMC.params$n.chains)
  loo.out <- loo(loglik, 
                 r_eff = Reff, 
                 cores = MCMC.params$n.chains)
  
  return(list(DIC = jm$DIC,
              loglik.obs = loglik,
              Reff = Reff,
              Rhat = Rhat,
              loo.out = loo.out))
  
}


# Function to convert character time (e.g., 1349) to minutes from 
# a particular start time of the day (e.g., 0700). Default is midnight (0000)
# Use as char_time2min(x, origin = "0000"). 
char_time2min <- function(x, origin = "0000"){
  chars.origin <- strsplit(origin, split = "") %>% unlist
  if (length(chars.origin) == 3){
    hr <- as.numeric(chars.origin[1])
    m <- as.numeric(c(chars.origin[2:3]))
    M.0 <- hr * 60 + m[1] * 10 + m[2]
  } else {
    hr <- as.numeric(chars.origin[1:2])
    m <- as.numeric(c(chars.origin[3:4]))
    M.0 <- (hr[1] * 10 + hr[2]) * 60 + m[1] * 10 + m[2]
  }
  
  if (!is.na(x)){
    chars <- strsplit(x, split = "") %>% unlist()
    if (length(chars) == 3){
      hr <- as.numeric(chars[1])
      m <- as.numeric(c(chars[2:3]))
      M.1 <- (hr * 60 + m[1] * 10 + m[2])
    } else {
      hr <- as.numeric(chars[1:2])
      m <- as.numeric(c(chars[3:4]))
      M.1 <- (hr[1] * 10 + hr[2]) * 60 + m[1] * 10 + m[2]
    }
  } else {
    M.1 <- NA
  }
  
  if (!is.na(M.1)){
    if (M.1 >= M.0){
      out <- M.1 - M.0
    } else {
      out <- 1440 - (M.0 - M.1)
    }
    
  } else {
    out <- NA
  }
  
  return(out)
}

# converts minutes since 0000 in integer to time in character
# minute2time_char(420) will return "700"
minutes2time_char <- function(min_0000){
  H <- trunc(min_0000/60)
  M <- formatC(((min_0000/60 - H) * 60), width = 2, flag = "0")
  
  out <- paste0(H, M)
  return(out)
}

# change max.shift if needed. max.shift can be up to 5
find.shift <- function(x0, max.shift = 4){
  x <- as.numeric(x0)
  if (!is.na(x)){
    if (x < 600){
      shift <- "1"
    } else if (x == 600) {
      shift <- "1/2"
    } else if (x > 600 & x < 780) {
      shift <- "2"
    } else if (x == 780){
      shift <- "2/3"
    } else if (x > 780 & x < 960){
      shift <- "3"
    } else if (x == 960){
      shift <- "3/4"
    } else if (x > 960 & x < 1140){
      shift <- "4"
    } else if (x == 1140){
      if (max.shift > 4){
        shift <- "4/5"        
      } else {
        shift <- "4"
      }
    } else if (x > 1140 & x <= 1320){ 
      shift <- "5"
    } else {
      shift <- NA
    }
  } else {
    shift <- NA
  }
  return(shift)
}

# x is a data.frame with at least three fields: Date (character), 
# Minutes_since_0000
# and Shift - find.shift is used to come up with this
# 1 = START EFFORT
#2 = CHANGE OBSERVERS
#3 = CHANGE SIGHTING CONDITIONS
#4 = GRAY WHALE SIGHTING
#5 = END EFFORT
#6 = OTHER SPECIES SIGHTING
# provide a data frame that came back from get.data function, hrs for 
# start and end of each day (default = 7 and 19, correspond to 0700
# and 1900), and the maximum number of shift per day (default to 4).
#find.effort <- function(x, start.hr = 7, end.hr = 19, max.shift = 4){
<<<<<<< HEAD
# T0 is start time in character, e.g., "0630", "0700)
find.effort <- function(x, T0){
=======
find.effort <- function(x){
>>>>>>> 5a1c84103eaf33894693d5605e13e48e252974bc
  # NEED TO ADD SHIFT INDEX. TO DO THAT, I NEED TO KNOW WHAT TIME THE OBSERVATION
  # STARTS EVERYDAY AND THE MAXIMUM NUMBER OF SHIFTS PER DAY, WHICH ARE NOT CONSISTENT
  # AMONG YEARS. I NEED TO THINK ABOUT THIS A BIT MORE... 2023-05-01
  # 
<<<<<<< HEAD
  # THE FUNCTION ABOVE find.shift DEFINES SHIFTS. ANYTIME BEFORE 1000 IS SHIFT 1, ETC.
  # get.data USES find.shift AND RETURNS ASSIGNED SHIFTS IN THE OUTPUT.
  
=======
  # REGARDLESS OF STARTING TIME, THEY SHOULD BE SEPARATED INTO 3-HR BLOCKS
>>>>>>> 5a1c84103eaf33894693d5605e13e48e252974bc
  
  # this turns dates in to character
  all.dates <- unique(x$Date)
  
<<<<<<< HEAD
  # Start time of shift 1:
  T0.minutes <- char_time2min(T0)
  
  # End of shift time
  shift.ends <- c(600, 780, 960, 1140, 1320)
  
  shift.begins <- c(T0.minutes, shift.ends)
  
=======
>>>>>>> 5a1c84103eaf33894693d5605e13e48e252974bc
  out.list <- list()
  d <- k1 <- c <- k2 <- 1
  for (d in 1:length(all.dates)){
    # pick just one day's worth of data
    one.day <- filter(x, Date == as.Date(all.dates[d])) %>% arrange(Minutes_since_0000)
    
    # go through one shift at a time
    for (k4 in 1:5){
      shift.idx <- grep(as.character(k4), one.day$Shift)
      
      one.shift <- one.day[shift.idx,]

      if (nrow(one.shift) > 0){
        # Sometimes the beginning of one shift and the end of the previous 
        # shift is shared in one line with Shift = x/y. When that and a sighting
        # happens simultaneously, the sighting gets double counted between the
        # two shifts. So, the sighting has to be placed in one or the other.
        line.bottom <- one.shift[nrow(one.shift),]
        if (line.bottom$Event == 4 & str_detect(line.bottom$Shift, "/")){
          one.shift <- one.shift[1:(nrow(one.shift)-1),]
          
        }
        
        # add one row at the top and end of one.shift, so that it has
        # Event 1 at the top, and 5 at the bottom if they are not there:
        if (one.shift[1,"Event"] != 1){
          one.shift.eft <- rbind(one.shift[1,], one.shift)
          one.shift.eft[1, "Event"] <- 1
          one.shift.eft[1, "Minutes_since_0000"] <- shift.begins[k4]
        } else {
          one.shift.eft <- one.shift
        }
        
        if (one.shift[nrow(one.shift), "Event"] != 5){
          one.shift.eft <- rbind(one.shift.eft, one.shift[nrow(one.shift),])
          one.shift.eft[nrow(one.shift.eft), "Event"] <- 5
          one.shift.eft[nrow(one.shift.eft), "Minutes_since_0000"] <- shift.ends[k4]
        }
        
        # find out how many on/off effort existed
        row.1 <- which(one.shift.eft$Event == 1)
        row.5 <- which(one.shift.eft$Event == 5)
        
        # sometimes too many event == 1 and event == 5
        if (length(row.1) > 1 & length(row.5) > 1){
          for (k3 in 2:length(row.1)){
            if (row.1[k3] < row.5[k3-1]){
              row.1[k3] <- NA
            } 
            
          }
          row.1 <- row.1[!is.na(row.1)]
          
        }
        
        # if they don't match, adjust accordingly.
        if (length(row.1) != length(row.5)){
          nrow <- min(length(row.1), length(row.5))
          row.1.1 <- vector(mode = "numeric", length = nrow)
          row.5.1 <- vector(mode = "numeric", length = nrow)
          for (k2 in 1:nrow){
            if (k2 == 1){
              row.1.1[k2] <- row.1[k2]
              row.5.1[k2] <- row.5[k2]
            } else {
              row.1.1[k2] <- first(row.1[row.1 > row.5.1[k2-1]])
              row.5.1[k2] <- first(row.5[row.5 > row.1.1[k2]])
            }
            
          }
          row.1 <- row.1.1[!is.na(row.1.1)]
          row.5 <- row.5.1[!is.na(row.5.1)]
        }
        
        
        # calculate effort for each "on" period per shift
        tmp.eft <- 0
        for (k2 in 1:length(row.1)){
          tmp <- one.shift.eft[row.1[k2]:row.5[k2],] 
          tmp.eft <- tmp.eft + (max(tmp$Minutes_since_0000) - min(tmp$Minutes_since_0000))  
          
        }
        
        # Sometimes, there is no Vis (or also sea state) update in an entire
        # shift. Use one from previous shift in those cases
        if (sum(!is.na(one.shift$SeaState)) > 0){
          max.sea.state <- max(one.shift$SeaState, na.rm = T)          
        } else {
          max.sea.state <- max.sea.state
        }

        if (sum(!is.na(one.shift$Vis)) > 0){
          max.Vis <- max(one.shift$Vis, na.rm = T) 
        } else {
          max.Vis <- max.Vis
        }
        
        out.list[[c]] <- data.frame(Date = all.dates[d],
                                    Minutes_since_0000 = shift.begins[k4],
                                    Shift = k4,
                                    Effort = tmp.eft,
                                    Mother_Calf = sum(one.shift$Mother_Calf, 
                                                      na.rm = T),
                                    Sea_State = ifelse(!is.infinite(max.sea.state),
                                                       max.sea.state, NA),
                                    Vis = ifelse(!is.infinite(max.Vis),
                                                 max.Vis, NA))
        
        c <- c + 1
        
      }
    }
    
    
  }
  
  out.df <- do.call(rbind, out.list)
  # out.df %>% 
  #   mutate(Date = as.Date(Date.char, 
  #                              format = "%Y-%m-%d")) -> out.df.1
  return(out.df)
}

format.output <- function(data.shift, max.shift){
  # create a data frame with the full set of date/shift for dates with observations
  day.shifts <- data.frame(Date = rep(unique(data.shift$Date),
                                           each = max.shift),
                           Shift = ifelse(max.shift == 4, 
                                          rep(c(1,2,3,4), 
                                              times = length(unique(data.shift$Date))),
                                          rep(c(1,2,3,4,5), 
                                              times = length(unique(data.shift$Date)))))
  # Combine the full set of date/shift with the observed - some shifts are NAs because
  # they were not in the dataset
  day.shifts %>% 
    left_join(data.shift, by = c("Date", "Shift")) -> all.day.shifts
  
  
  # create a vector with sequential weeks
  all.weeks <- seq.Date(as.Date(min(data.shift$Date)),
                        as.Date(max(data.shift$Date)),
                        by = "week")
  
  # select necessary data from per-shift data frame, mutate the column names
  # the create a new data frame
  data.shift %>% 
    select(Shift, Date, Effort, Mother_Calf) %>%
    mutate(Date = Date,
           Effort = Effort/60,
           Sightings = Mother_Calf) %>%
    select(Date, Shift, Effort, Sightings) %>%
    #mutate(Date = as.Date(Date)) %>%
    data.frame() -> raw.data
  
  # Create all dates, including weekends
  all.dates <- seq.Date(as.Date(min(data.shift$Date)),
                        as.Date(max(data.shift$Date)),
                        by = "day")
  
  # create all shists, incluyding nights
  all.shifts <- data.frame(Date = rep(all.dates,
                                           each = 8),
                           Shift = rep(c(1:8), 
                                       times = length(all.dates),
                                       by = "day"))
  
  all.shifts %>% 
    left_join(raw.data, by = c("Date", "Shift")) %>%
    mutate(Week = ceiling(difftime(Date, min(all.dates), 
                                   units = "weeks")) %>%
             as.numeric(),
           Date = Date) %>%
    select(Week, Date, Shift, Effort, Sightings) -> formatted.all.data
  
  # need to change week = 0 to week = 1...
  formatted.all.data[formatted.all.data$Week == 0, "Week"] <- 1
  
  # Change NAs to 0s
  formatted.all.data[is.na(formatted.all.data)] <- 0
  
  return(formatted.all.data)
}
