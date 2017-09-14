;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;; Description
;;; Author         Michael Kappert 2017
;;; Last Modified <michael 2017-09-14 22:41:03>

(defpackage "VIRTUALHELM"
  (:nicknames "VH")
  (:use "COMMON-LISP"
        #+sbcl "SB-MOP"
        "POLARCL"
        "CL-GRIB2"
        "CFFI"
        "LOCAL-TIME"
        "BABEL")
  (:export
   ;; HTTP API
   "getWind"
   "setRoute"
   "setParameter"
   "getRoute"
   "getWindAtPosition"
   ;; VH backend
   "*MAP-FILE*"
   "*GRIB-FOLDER*"
   "RUN-VIRTUAL-HELM"))

;;; EOF
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
