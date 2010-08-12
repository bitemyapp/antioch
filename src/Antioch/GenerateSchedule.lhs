> module Antioch.GenerateSchedule where

> import Antioch.Generators
> import Antioch.Types
> --import Antioch.TimeAccounting
> --import Antioch.SLALib  (slaGaleq)
> --import Antioch.Utilities
> import Antioch.DateTime
> import Antioch.Filters (filterHistory)
> --import Data.Char
> import Data.List 
> --import Data.Maybe      (isJust, maybeToList)
> --import System.Random   (getStdGen, setStdGen, mkStdGen)
> --import System.Random
> import Test.QuickCheck hiding (frequency)
> --import qualified Test.QuickCheck as T
> --import Control.Monad.RWS.Strict
> --import System.IO.Unsafe  (unsafePerformIO)



This is a top level function for not just producing a set of Projects (w/
their related child Sessions), but also pre-scheduled periods of different
Session types (Fixed, Windowed, and the special case of Maintenance).
The user can specify:
   * the time range over which we want our pre-scheduled periods 
   * whether to create Maintenance periods
   * the rough ratio between Open, Fixed, and Windowed Session hours.
   * how much extra time to give to Open sessions as 'backlog'

> genSimTime :: DateTime -> Int -> Bool -> (Float, Float, Float) -> Float -> Gen [Project]
> genSimTime start days useMaint (open, fixed, windowed) backlog = do
>     -- TBF: assert that open + fixed + windowed == 1.0 ?
>     -- TBF: assert that backlog < 1.0 ?
>     -- create the maintenance schedule first to see how much time it is
>     maint <- genMaintenanceProj start days
>     let schedule = if useMaint then concatMap periods $ sessions maint else []
>     let maintHrs = if useMaint then (/60) . fromIntegral . sum $ map duration schedule else 0.0
>     -- the remaining time now gets split up by type
>     let simHrs = days*24
>     let hrs'' = (fromIntegral simHrs) - maintHrs
>     let hrs' = if hrs'' < 0 then 0 else hrs''
>     -- how much for fixed and windowed is straightforward
>     let fixedHrs    = round $ fixed    * hrs'
>     let windowedHrs = round $ windowed * hrs'
>     -- how much for open must include the backlog
>     let backlogHrs  = round $ backlog  * hrs'
>     let openHrs'    = round $ open     * hrs'
>     let openHrs     = openHrs' + backlogHrs
>     oProjs <- genProjectsByHrs Open openHrs 
>     -- Becasuse we must build a schedule that has no overlaps,
>     -- it's easiest to first assign the periods to the schedule,
>     -- then assign sessions & projects to these periods
>     -- First, the windowed periods
>     -- TBF: for now, we can treat windowed like fixed
>     winPeriods <- genWindowedSchedule start days schedule windowedHrs
>     wProjs <- genWindowedProjects  winPeriods --genWindowedProjects winPeriods
>     let schedule' = sort $ schedule ++ (concat winPeriods)
>     -- Now, the fixed periods
>     fixedPeriods <- genFixedSchedule start days schedule' fixedHrs
>     fProjs <- genFixedProjects fixedPeriods
>     -- Finally, put all the projects togethor
>     return $ oProjs ++ wProjs ++ fProjs ++ if useMaint then [maint] else []

Generate projects such that the sum of their allotted hours is equal to 
our greater then the specified amount.

> genProjectsByHrs :: SessionType -> Int -> Gen [Project]
> genProjectsByHrs _ 0 = return []
> genProjectsByHrs stype hrs | hrs < 0 = genProjectsByHrs stype 0
>                            | otherwise = do
>   p <- genProjectByType stype
>   pp <- genProjectsByHrs stype $ hrs - ((`div` 60) . pAllottedS $ p)
>   return $ p : pp

TBF: we don't really need this anymore

> genProjectByType :: SessionType -> Gen Project
> genProjectByType Open     = genProject

TBF: for now keep it real simple - a single proj & sess for each period

> genFixedProjects :: [Period] -> Gen [Project]
> genFixedProjects [] = return []
> genFixedProjects (p:ps) = do
>   proj <- genFixedProject  p
>   projs <- genFixedProjects ps
>   return $ proj : projs --genFixedProjects ps

> genFixedProject :: Period -> Gen Project
> genFixedProject p = do
>   proj' <- genProject
>   let total = duration p
>   let s'' = head . sessions $ proj'
>   let s' = s'' { sType = Fixed
>                , sName = "FixedS"
>                , sAllottedS = total
>                , sAllottedT = total
>                , ra = 0.0
>                , dec = 1.5 -- TBF: this is just always up
>                }
>   let s = makeSession s' [] [p]
>   return $ makeProject proj' total total [s]

Here we randomly generate periods in the given year that DON'T cause
overlaps until we run out of time.

> genFixedSchedule :: DateTime -> Int -> [Period] -> Int -> Gen [Period]
> genFixedSchedule _ _ _ 0 = return []
> genFixedSchedule start days ps hrs | hrs < 0 = genFixedSchedule start days ps 0
>                                    | otherwise = do
>     p <- genFixedPeriod start days
>     --pp <- genFixedSchedule year ps $ hrs' p
>     --return $ p : pp
>     let ps' = sort $ ps ++ [p]
>     --case (internalConflicts (sort $ ps ++ [p])) of
>     case (internalConflicts ps') of
>       False -> do
>           pp <- genFixedSchedule start days ps' $ hrs' p
>           return $ p : pp
>       True -> genFixedSchedule start days ps hrs
>   where
>     hrs' p = hrs - ((`div` 60) . duration $ p)

> genFixedPeriod :: DateTime -> Int -> Gen Period
> genFixedPeriod start days = do
>   day <- choose (1, days)
>   hour <- choose (0, 23)
>   duration <- choose (1, 8)
>   return $ defaultPeriod { startTime = start' day hour
>                          , duration  = duration*60
>                          , pState    = Scheduled
>                          }
>     where
>   start' day hour = addMinutes' ((day*24*60)+(hour*60)) start

> genWindowedSchedule :: DateTime -> Int -> [Period] -> Int -> Gen [[Period]]
> genWindowedSchedule _ _ _ 0 = return []
> genWindowedSchedule start days ps hrs | hrs < 0 = genWindowedSchedule start days ps 0
>                                       | otherwise = do
>     wp <- genWindowedPeriods start days
>     let ps' = sort $ ps ++ wp 
>     case (internalConflicts ps') of
>       False -> do
>           pp <- genWindowedSchedule start days ps' $ hrs' wp
>           return $! wp:pp
>       True -> genWindowedSchedule start days ps hrs
>   where
>     hrs' wp = hrs - ((`div` 60) . sum $ map duration wp)

> genWindowedPeriods :: DateTime -> Int -> Gen [Period]
> genWindowedPeriods start days = do
>   numWindows <- choose (3,10)
>   intervalDays <- choose (15, 60)
>   let sizeDays' = numWindows * intervalDays
>   let sizeDays = if (sizeDays' >= days) then days - 3 else sizeDays'
>   day <- choose (1, days - 1) --sizeDays)
>   hour <- choose (0, 23)
>   duration <- choose (1, 8) -- hours
>   let firstStart = getStart day hour
>   let dts = filter (<end) $ [addMinutes' (d*24*60) firstStart | d <- [0, intervalDays .. (numWindows * intervalDays)]]
>   return $! map (mkPeriod duration) dts 
>     where
>   end = addMinutes' (days*24*60) start
>   getStart day hour = addMinutes' ((day*24*60)+(hour*60)) start
>   mkPeriod dur dt = defaultPeriod { startTime = dt
>                                   , duration  = dur*60
>                                   , pState    = Scheduled }

TBF: for now keep it real simple - a single proj & sess for each set of periods

> genWindowedProjects :: [[Period]] -> Gen [Project]
> genWindowedProjects [] = return []
> genWindowedProjects (wp:wps) = do
>   proj <- genWindowedProject  wp
>   projs <- genWindowedProjects wps
>   return $ proj : projs --genFixedProjects ps

> genWindowedProject :: [Period] -> Gen Project
> genWindowedProject wp = do
>   proj'' <- genProject
>   let proj' = proj'' { pName = "WinP" }
>   let total = sum $ map duration wp
>   let s'' = head . sessions $ proj'
>   let s' = s'' { sType = Windowed
>                , sName = "WinS"
>                , sAllottedS = total
>                , sAllottedT = total
>                , ra = 0.0
>                , dec = 1.5 -- TBF: this is just always up
>                }
>   -- TBF: do we really need to create windows for this?
>   let s = makeSession s' [] wp
>   return $ makeProject proj' total total [s]


Creates a maintenance project with a year's worth of pre-scheduled periods
reflecting a realistic maintenance schedule.

> genMaintenanceProj :: DateTime -> Int -> Gen Project
> genMaintenanceProj start days = do
>   let project' = mkMaintProject start
>   let session'' = mkMaintSession
>   mntPeriods <- genMaintenancePeriods start days session''
>   let totalTime = sum $ map duration mntPeriods
>   let session' = session'' { sAllottedT = totalTime, sAllottedS = totalTime } 
>   let session = makeSession session' [] mntPeriods
>   return $ makeProject project' totalTime totalTime [session]

> genMaintenancePeriods :: DateTime -> Int -> Session -> Gen [Period]
> genMaintenancePeriods start days s = do
>   let end = addMinutes' (days*24*60) start
>   let (lastYear, _, _, _, _, _) = toGregorian end
>   let (firstYear, _, _, _, _, _) = toGregorian start
>   ps <- mapM (genMaintenancePeriodsByYear s) [firstYear .. lastYear]
>   return $ filterHistory (concat ps) start days
>     where
>       
> genMaintenancePeriodsByYear :: Session -> Int -> Gen [Period]
> genMaintenancePeriodsByYear s year = do
>   let summerMaint = createSummerMaintenance year s
>   springMaint <- genWeeklyMaintPeriods springStart springEnd s
>   fallMaint <- genWeeklyMaintPeriods fallStart fallEnd s
>   return $ nub . sort $ springMaint ++ summerMaint ++ fallMaint
>     where
>       springStart = fromGregorian year 1 1 0 0 0  
>       springEnd   = fromGregorian year 6 1 0 0 0  
>       fallStart = fromGregorian year 9 15 0 0 0  
>       fallEnd   = fromGregorian (year+1) 1 1 0 0 0  

> mkMaintProject :: DateTime -> Project
> mkMaintProject start = defaultProject { pName = "Maintenance"
>                                      , semester = sem sem'}
>   where
>     (year, _, _, _, _, _) = toGregorian start 
>     sem' = (show $ year - 2000) ++ "A"
>     sem s = if (length s) == 2 then "0" ++ s else s
>      

> mkMaintSession :: Session
> mkMaintSession = defaultSession { sName = "Maintenance"
>                                 , frequency = 2.0
>                                 , band = L
>                                 , ra = 0.0
>                                 , dec = 1.5 -- TBF: this is just always up
>                                 , receivers = [[Rcvr1_2]]
>                                 , sType = Fixed }

TBF: this will make an 8 hour maintenance day every 7 days - but we want it 
to be randomly placed in the middle 5 days of each week.

> genWeeklyMaintPeriods :: DateTime -> DateTime -> Session -> Gen [Period]
> genWeeklyMaintPeriods start end s = return $ filter (\p -> (startTime p) < end) $ map (mkMaintPeriod s (8*60)) $ dts numWeeks
>   where
>     numWeeks = round $ (fromIntegral $ end - start) / (60*60*24*7)
>     dts numWeeks = [(week*7*24*60) `addMinutes'` start | week <- [0 .. numWeeks]]

We don't care about getting the days of the week correclty, as long
as we have:
   * during the summer months we have 4 days of 10 hour maintenance followed 
     by three free days
   * during the non-summer months, one random 8 hour maintenance day in the 
     middle 5 days of each 7 days (week)

> createSummerMaintenance :: Int -> Session -> [Period]
> createSummerMaintenance year s = concatMap mkMaintWeek $ weekDts summerStart numWeeks
>   where
>     summerStart = fromGregorian year 6 1 0 0 0 
>     summerEnd   = fromGregorian year 9 1 0 0 0 
>     numWeeks = round $ (fromIntegral $ summerEnd - summerStart) / (60*60*24*7)
>     weekDts start numWeeks = [(week*7*24*60) `addMinutes'` start | week <- [0 .. numWeeks]]
>     dayDts start = [(day*24*60) `addMinutes'` start | day <- [1 .. 4]]
>     mkMaintWeek start = map (mkMaintPeriod s (10*60)) $ dayDts start

> mkMaintPeriod :: Session -> Minutes -> DateTime -> Period
> mkMaintPeriod s dur date = defaultPeriod { startTime = start
>                                     , session = s
>                                     , duration = dur
>                                     , pState = Scheduled 
>                                     }
>   where
>     -- all maintenance periods start at 8 AM ET
>     (year, month, day, _, _, _) = toGregorian date
>     start = fromGregorian year month day (8+4) 0 0 -- UTC!
