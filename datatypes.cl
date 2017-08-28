;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;; Description
;;; Author         Michael Kappert 2017
;;; Last Modified <michael 2017-08-28 23:28:59>

(in-package :virtualhelm)

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;; Data structures

;; TODO: A latlng should only be used to represent Google Maps coordinates.
(defstruct latlng lat lng)


(defstruct dms (degrees 0) (minutes 0) (seconds 0))

(defun dms2decimal (dms)
  (+ (dms-degrees dms)
     (/ (dms-minutes dms) 60)
     (/ (dms-seconds dms) 3600)))

(defun decimal2dms (dec)
  (multiple-value-bind (d r1)
      (truncate dec)
    (multiple-value-bind (m r2)
        (truncate (* r1 60))
      (make-dms :degrees d :minutes m :seconds (* r2 60)))))

(defstruct gribfile
  "Basic / common GRIB data"
  timespec                      ; The timespec (yyyymmdd, hh) specifying the DWD ICON data files
  forecast-time
  grid-size                     ; Number of data points, should equal lat-points * lon-points
  step-units
  lat-start lat-end lat-points  ; Start, end and number of points along parallel
  lon-start lon-end lon-points  ; Start, end and number of points along meridian
  i-inc j-inc
  i-scan-neg j-scan-pos
  data                          ; Array of forecast data for successive forecast times
  )

(defmethod print-object ((thing gribfile) stream)
  (format stream "{gribfile <~a,~a>/<~a,~a> ~a}"
          (gribfile-lat-start thing)
          (gribfile-lon-start thing)
          (gribfile-lat-end thing)
          (gribfile-lon-end thing)
          (gribfile-timespec thing)))

(defstruct grib-filespec
  region
  resolution
  date)

(defun format-timespec-datehh (stream timestamp &key (timezone +utc-zone+) (offset 0))
  "Format timestamp as YYYY-MM-DD, HH Uhr"
  (format-timestring stream
                     (adjust-timestamp timestamp (offset :hour offset))
                     :format '((:year 4) "-" (:month 2) "-" (:day 2) ", " (:hour 2) "Uhr") :timezone timezone))  

(defmethod print-object ((thing timestamp) stream)
  (format-timespec-datehh stream thing))

(defstruct grib-values
  forecast-time                 ; 
  u-array
  v-array
  vmax-data)

(defmethod print-object ((thing grib-values) stream)
  (format stream "{grib-values ~a ~a}"
          (grib-values-forecast-time thing)
          (array-dimensions
           (grib-values-u-array thing))))

;;; EOF
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
