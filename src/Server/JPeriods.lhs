Copyright (C) 2011 Associated Universities, Inc. Washington DC, USA.

This program is free software; you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation; either version 2 of the License, or
(at your option) any later version.

This program is distributed in the hope that it will be useful, but
WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU
General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program; if not, write to the Free Software
Foundation, Inc., 675 Mass Ave, Cambridge, MA 02139, USA.

Correspondence concerning GBT software should be addressed as follows:
      GBT Operations
      National Radio Astronomy Observatory
      P. O. Box 2
      Green Bank, WV 24944-0002 USA

> module Server.JPeriods where

> import Control.Monad.Trans                   (liftIO)
> import Control.Monad.State.Lazy              (StateT)
> import Data.Record.Label
> import Data.List                             (intercalate)
> import Data.Maybe                            (maybeToList)
> import Database.HDBC
> import Database.HDBC.PostgreSQL              (Connection)
> import Network.Protocol.Http
> import Network.Protocol.Uri
> import Network.Salvia.Handlers.Error         (hError)
> import Network.Salvia.Handlers.MethodRouter  (hMethodRouter)
> import Network.Salvia.Httpd
> import qualified Data.ByteString.Lazy.Char8 as L
> import Server.Json
> import Server.List
> -- this works!
> -- import Antioch.Reports

NOTE: this is code responsible for returning JSON representations of Periods
read from the DSS data base.  This code has been checked in as an example
of working code, since there are no available examples on the web that I
can find.  Nothing in DSS is currently using this code.

> data JPeriod = JPeriod {
>       jperiod_id :: Int
>     , session_id :: Maybe Int
>     , start_time :: Maybe String
>     , duration :: Maybe Double
> } deriving Show

> defaultJPeriod = JPeriod {
>       jperiod_id = 0
>     , session_id = Nothing 
>     , start_time = Nothing
>     , duration = Nothing
> }

> instance JSON JPeriod where
>     readJSON = jsonToJPeriod
>     showJSON = jperiodToJson

> jsonToJPeriod _ = undefined

> jperiodToJson :: JPeriod -> JSValue
> jperiodToJson period = makeObj $
>       ("id", showJSON . jperiod_id $ period)
>     : concatMap field [
>           ("session_id",      showJSON' . session_id )
>         , ("start_time",      showJSON' . start_time)
>         , ("duration",        showJSON' . duration)
>       ]
>   where
>     field (name, accessor) = maybeToList . fmap ((,) name) . accessor $ period

> showJSON' :: JSON a => Maybe a -> Maybe JSValue
> showJSON' = fmap showJSON

> periodsHandler     :: Connection -> Handler ()
> periodsHandler cnn = hMethodRouter [
>       (GET,  listPeriods cnn)
>     --, (POST, handlePost cnn)
>     ] $ hError NotFound

> listPeriods :: (IConnection conn) => conn -> StateT Context IO ()
> listPeriods cnn = do
>     -- try scheduling! this actually works!
>     --liftIO $ sim09B 4 "sims" 
>     liftIO $ print "querying periods from DB!"
>     rst <- liftIO $ quickQuery' cnn query []
>     let periods = map buildPeriod rst
>     jsonHandler $ makeObj [("periods", showJSON periods)]
>     liftIO $ print "finished listPeriods"
>   where
>     query           = "SELECT id, session_id, start, duration FROM periods"
>     buildPeriod xs = defaultJPeriod {
>         jperiod_id   = fromSql $ xs !! 0
>       , session_id   = fromSql $ xs !! 1
>       , start_time   = fromSql $ xs !! 2
>       , duration     = fromSql $ xs !! 3
>       }
