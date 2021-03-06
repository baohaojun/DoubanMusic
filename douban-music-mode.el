;; -*- Emacs-Lisp -*-
;; -*- coding: utf-8; -*-
;;; douban-music-mode.el ---
;; Time-stamp: <2013-05-07 17:54:04 Tuesday by lzy>

;; Copyright (C) 2013 zhengyu li
;;
;; Author: zhengyu li <lizhengyu419@gmail.com>
;; Keywords: douban

;; version: 1.1

;; This file is not part of GNU Emacs.

;; This program is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with this program.  If not, see <http://www.gnu.org/licenses/>.

;;; Commentary:
;;
;; Put this file into your load-path and the following into your ~/.emacs:
;;
;; Installation:
;; add the following lines into your configuration file
;;
;;   (autoload 'douban-music "douban-music-mode" nil t)

;; 2012-05-06: zhengyu li <lizhengyu419@gmail.com>
;;   add pause seek forward/backward for mplayer
;;   don't save all song's pictures to local

;; 2012-05-05: zhengyu li <lizhengyu419@gmail.com>
;;   add mplayer support
;;   add default channel selection
;;   specify utf-8 coding
;;   add detail song's info showing

;; 2012-05-03: zhengyu li <lizhengyu419@gmail.com>
;;   the first version
;;
;;; Code:

(require 'json)
(require 'assoc)
(require 'url-http)

(defgroup douban-music nil
  "Douban music group"
  :group 'entertainment)

(defcustom douban-music-cache-directory "~/.emacs.d/DouBanMusic/"
  "Default cache directory of douban music mode"
  :type 'string
  :group 'douban-music)

(defcustom douban-music-default-channel 0
  "Default channel for douban music"
  :type 'number
  :group 'douban-music)

(defcustom douban-music-player "mplayer"
  "Player for douban music."
  :type 'string
  :group 'douban-music)

(defcustom douban-song-before-info-hook nil
  "Hook to run before fetch the song's info.")

(defcustom douban-song-info-complete-hook nil
  "Hook run when song infomation is complete (the image is downloaded).

You can use this as an opportunity to show the current song in
system notification, just as rythombox does."
  :group 'douban-music
  :type 'hook)

(defface douban-music-track-face
  '((t (:height 1.2 :foreground "Grey70")))
  "Face for douban music track"
  :group 'douban-music)

(defface douban-music-tag-face
  '((t (:height 1.1 :foreground "Steelblue1")))
  "Face for douban music tag"
  :group 'douban-music)

(defface douban-music-title-face
  '((t (:height 1.05 :foreground "Grey65")))
  "Face for douban music title"
  :group 'douban-music)

(defface douban-music-album-face
  '((t (:height 1.05 :foreground "Red3")))
  "Face for douban music album"
  :group 'douban-music)

(defface douban-music-artist-face
  '((t (:height 1.05 :foreground "RoyalBlue")))
  "Face for douban music artist"
  :group 'douban-music)

(defface douban-music-company-face
  '((t (:height 1.05 :foreground "Yellow")))
  "Face for douban music publish company"
  :group 'douban-music)

(defface douban-music-publish-year-face
  '((t (:height 1.05 :foreground "Green")))
  "Face for douban music publish year"
  :group 'douban-music)

(defconst douban-music-buffer-name "Douban Music" "Douban music buffer name")

(defconst douban-music-get-channels-url "http://www.douban.com/j/app/radio/channels"
  "Douban channel to retrive url.")

(defconst douban-music-get-song-list-url "http://www.douban.com/j/app/radio/people?app_name=radio_desktop_win&version=100&channel=%s&type=n"
  "Url to fetch song list from douban music server.")

(defconst douban-music-channels-delimiter "==================================================================================================="
  "Delimiter for channels show")

;; Internal variables
(defvar douban-music-local-url nil "The local saved mp3 to play instead of http://...")
(defvar douban-music-local-icon nil "The local saved icon to display.")
(defvar douban-music-song-list nil "Song list for current channel.")
(defvar douban-music-song-json [] "The json returned.")
(defvar douban-music-current-song nil "Song currently playing.")
(defvar douban-music-channels nil "Total channels for douban music.")
(defvar douban-music-current-channel nil "Current channel for douban music.")
(defvar douban-music-current-status "stopped" "Douban music current status.")
(defvar douban-music-current-process nil "Current play process of douban music.")
(defvar douban-music-image-file "image" "Image file used to save picture of current song")
(defvar douban-music-indent0 " " "0-level indentation.")
(defvar douban-music-indent1 "  " "1-level indentation.")
(defvar douban-music-indent2 "    " "2-level indentation.")
(defvar douban-music-indent3 "     " "3-level indentation.")
(defvar douban-music-indent4 "          " "4-level indentation.")
(defvar douban-music-should-replay nil "Should replay the song.")
(defvar douban-music-not-playing 0 "How many times we chose not to play the songs.")
(defvar douban-music-alive nil "Douban is alive.")

;; key map definition
(defvar douban-music-mode-map nil
  "Keymap for doubban music mode")

(setq douban-music-mode-map
      (let ((map (make-sparse-keymap)))
        (define-key map (kbd "RET") 'douban-music-goto-current-playing)
        (define-key map "s" 'douban-music-stop)
        (define-key map "g" 'douban-music-refresh)
        (define-key map "j" 'douban-music-goto-current-playing)
        (define-key map "c" 'douban-music-set-channel)
        (define-key map "n" 'douban-music-play-next-refresh)
        (define-key map "p" 'douban-music-play-previous)
        (define-key map "q" 'douban-music-bury-buffer)
        (define-key map "x" 'douban-music-quit)
        (define-key map "z" 'douban-music-current-song-info)
        (if (string-match douban-music-player "mplayer")
            (progn
              (define-key map " " 'douban-music-pause/resume)
              (define-key map "<" 'douban-music-seek-backward)
              (define-key map ">" 'douban-music-seek-forward)))
        map))

(defun douban-music-pause/resume ()
  (interactive)
  (if (string-match douban-music-current-status "playing")
      (progn
        (setq douban-music-current-status "paused")
        (process-send-string douban-music-current-process "pause\n"))
    (if (string-match douban-music-current-status "paused")
        (progn
          (setq douban-music-current-status "playing")
          (process-send-string douban-music-current-process "pause\n")))))

(defun douban-music-seek-forward (&optional seconds)
  (interactive)
  (setq seconds (or seconds 5))
  (process-send-string douban-music-current-process (format "seek %d\n" seconds)))

(defun douban-music-seek-backward (&optional seconds)
  (interactive)
  (setq seconds (or seconds 5))
  (process-send-string douban-music-current-process (format "seek -%d\n" seconds)))

(defun douban-music-stop ()
  (interactive)
  (douban-music-kill-process)
  (setq douban-music-current-status "stopped")
  (setq douban-music-current-process nil))

(defun douban-music-refresh ()
  (interactive)
  (douban-music-get-song-list-async
   (lambda (&rest callback-args)
     (message "music refresh %s" (current-buffer))
     (douban-music-get-song-list (current-buffer))
     (douban-music-kill-process)
     (douban-music-play))))

(defun douban-music-goto-current-playing ()
  (interactive)
  (if (string-match douban-music-current-status "playing")
      (douban-music-interface-update)
    (if (string-match douban-music-current-status "stopped")
        (douban-music-play)
      (if (string-match douban-music-current-status "paused")
          (douban-music-pause/resume)
        (error "Unknown status")))))

(defun douban-music-next-channel ()
  "Switch to the next channel."
  (let ((cn douban-music-current-channel)
	(channels douban-music-channels))
    (while (and channels (>= cn (caar channels)))
      (setq channels (cdr channels)))
    (setq cn (or (caar channels) (caar douban-music-channels)))
    (douban-music-set-channel cn)))

(defun douban-music-prev-channel ()
  "Switch to the prev channel."
    (let ((cn douban-music-current-channel)
	  (channels (reverse douban-music-channels)))
      (while (and channels (<= cn (caar channels)))
	(setq channels (cdr channels)))
      (setq cn (or (caar channels) (caar (last douban-music-channels))))
      (douban-music-set-channel cn)))

(defun douban-music-set-channel (channel-number)
  (interactive "nChannel number:")
  (if (assoc channel-number douban-music-channels)
      (progn
        (setq douban-music-current-channel channel-number)
        (message (format "Change to channel: %s"
                         (cdr (assoc channel-number douban-music-channels))))
        (douban-music-refresh))
    (message "Warnning: not exist channel")))

(defun douban-music-play-next ()
  (interactive)
  (douban-music-kill-process)
  (douban-music-get-next-song)
  (douban-music-play))

(defun douban-music-play-next-refresh ()
  (interactive)
  (let ((previous-song douban-music-current-song)
        (should-replay douban-music-should-replay))
    (douban-music-kill-process)
    (if (or douban-music-should-replay (file-exists-p "~/.cache/system-config/logs/douban-should-loop"))
        (setq douban-music-should-replay nil)
      (douban-music-get-next-song))
    (if (and (>= previous-song douban-music-current-song)
             (not should-replay))
        (let ((r (random 11)))
          (cond
           ((> r 8)
            (setq douban-music-current-channel 22))
           ((> r 6)
            (setq douban-music-current-channel 17))
           (t
            (setq douban-music-current-channel r)))
          (douban-music-refresh))
      (douban-music-play))))

(defun douban-music-play-previous ()
  (interactive)
  (douban-music-kill-process)
  (douban-music-get-previous-song)
  (douban-music-play))

(defun douban-music-current-song-info ()
  (interactive)
  (princ (elt douban-music-song-list
              douban-music-current-song)))

(defun douban-music-bury-buffer ()
  (interactive)
  (when (eq major-mode 'douban-music-mode)
    (if (fboundp 'quit-window)
        (quit-window)
      (bury-buffer))))

(defun douban-music-quit ()
  (interactive)
  (when (eq major-mode 'douban-music-mode)
    (douban-music-stop)
    (kill-buffer (current-buffer))))

(defun douban-music-play ()
  (unless (and douban-music-current-process
               (process-live-p douban-music-current-process))
    (run-hooks 'douban-song-before-info-hook)
    (let (song)
      (setq song (elt douban-music-song-list
                      douban-music-current-song))
      (unless song
	(error "Get song from song list failed"))
      (douban-music-interface-update)
      (setq douban-music-current-process
	    (if (and douban-music-local-url (string= douban-music-local-url "/dev/null"))
		(start-process "douban-music-proc" nil "sleep" "1")
	      (start-process "douban-music-proc"
			     nil
			     douban-music-player
			     (if (string-match douban-music-player "mplayer")
				 "-slave"
			       "")
			     (or 
			      douban-music-local-url
			      (aget song 'url)))))
      (set-process-sentinel
       douban-music-current-process
       'douban-music-proc-sentinel)
      (setq douban-music-current-status "playing"))))

(defun douban-music-proc-sentinel (proc event)
  (unless (process-live-p proc)
    (douban-music-kill-process)
    (douban-music-play-next-refresh)))

(defun douban-music-get-previous-song ()
  (if (null douban-music-song-list)
      (error "song list is null")
    (setq douban-music-current-song (mod (- douban-music-current-song 1)
                                         (length douban-music-song-list)))))

(defun douban-music-get-next-song ()
  (if (null douban-music-song-list)
      (error "song list is null")
    (setq douban-music-current-song (mod (+ douban-music-current-song 1)
                                         (length douban-music-song-list)))))

(defun douban-music-kill-process ()
  (dolist (elt (process-list))
    (when (string-match "douban-music-proc" (process-name elt))
      (set-process-sentinel elt nil)
      (delete-process elt))))

(defun douban--make-sure-int (int-or-str)
  (if (stringp int-or-str)
      (string-to-number int-or-str)
    int-or-str))

(defconst douban--channel-string (replace-regexp-in-string "'" "\"" "{'channels':[{'name_en':'Personal Radio','seq_id':0,'abbr_en':'My','name':'私人兆赫','channel_id':0},{'name':'华语','seq_id':0,'abbr_en':'','channel_id':'1','name_en':''},{'name':'欧美','seq_id':1,'abbr_en':'','channel_id':'2','name_en':''},{'name':'七零','seq_id':2,'abbr_en':'','channel_id':'3','name_en':''},{'name':'八零','seq_id':3,'abbr_en':'','channel_id':'4','name_en':''},{'name':'九零','seq_id':4,'abbr_en':'','channel_id':'5','name_en':''},{'name':'粤语','seq_id':5,'abbr_en':'','channel_id':'6','name_en':''},{'name':'摇滚','seq_id':6,'abbr_en':'','channel_id':'7','name_en':''},{'name':'民谣','seq_id':7,'abbr_en':'','channel_id':'8','name_en':''},{'name':'轻音乐','seq_id':8,'abbr_en':'','channel_id':'9','name_en':''},{'name':'原声','seq_id':9,'abbr_en':'','channel_id':'10','name_en':''},{'name':'爵士','seq_id':10,'abbr_en':'','channel_id':'13','name_en':''},{'name':'电子','seq_id':11,'abbr_en':'','channel_id':'14','name_en':''},{'name':'说唱','seq_id':12,'abbr_en':'','channel_id':'15','name_en':''},{'name':'R&B ','seq_id':13,'abbr_en':'','channel_id':'16','name_en':''},{'name':'日语','seq_id':14,'abbr_en':'','channel_id':'17','name_en':''},{'name':'韩语','seq_id':15,'abbr_en':'','channel_id':'18','name_en':''},{'name':'女声','seq_id':16,'abbr_en':'','channel_id':'20','name_en':''},{'name':'法语','seq_id':17,'abbr_en':'','channel_id':'22','name_en':''},{'name':'古典','seq_id':18,'abbr_en':'','channel_id':'27','name_en':''},{'name':'动漫','seq_id':19,'abbr_en':'','channel_id':'28','name_en':''},{'name':'咖啡馆','seq_id':20,'abbr_en':'','channel_id':'32','name_en':''},{'name':'圣诞','seq_id':21,'abbr_en':'','channel_id':'170','name_en':''},{'name':'豆瓣好歌曲','seq_id':22,'abbr_en':'','channel_id':'179','name_en':''},{'name':'世界音乐','seq_id':23,'abbr_en':'','channel_id':'187','name_en':''},{'name':'布鲁斯','seq_id':24,'abbr_en':'','channel_id':'188','name_en':''},{'name':'新歌','seq_id':25,'abbr_en':'','channel_id':'61','name_en':''},{'name':'雷鬼','seq_id':26,'abbr_en':'','channel_id':'190','name_en':''},{'name':'新青年','seq_id':27,'abbr_en':'','channel_id':'196','name_en':''},{'name':'世界杯','seq_id':28,'abbr_en':'','channel_id':'201','name_en':''},{'name':'小清新','seq_id':29,'abbr_en':'','channel_id':'76','name_en':''},{'name':'Easy ','seq_id':30,'abbr_en':'','channel_id':'77','name_en':''},{'name':'91.1 ','seq_id':31,'abbr_en':'','channel_id':'78','name_en':''},{'name':'“砖”属音乐','seq_id':32,'abbr_en':'','channel_id':'145','name_en':''},{'name':'Pop','seq_id':33,'abbr_en':'','channel_id':'194','name_en':''},{'name':'拉丁','seq_id':34,'abbr_en':'','channel_id':'189','name_en':''},{'name':'草莓乐堡酒镇','seq_id':35,'abbr_en':'','channel_id':'245','name_en':''}]}"))

(defun douban-music-get-channels ()
  "Get channels from douban music server"
  (let ((json-buffer (douban-music-send-url
                      douban-music-get-channels-url))
        jason-start
        json-end
        jason)
    (with-current-buffer json-buffer
      (goto-char (point-min))

      (setq json
            (cdr (assoc 'channels
                        (json-read-from-string
                         (if (not (search-forward "channels" nil t))
                             douban--channel-string
                           (setq json-start (line-beginning-position))
                           (setq json-end (line-end-position))
                           (decode-coding-string
                            (buffer-substring-no-properties
                             json-start json-end) 'utf-8))))))
      (if (not (vectorp json))
          (error "Invalid data format")
        (setq douban-music-channels nil)
        (dotimes (i (length json))
          (let ((var (aref json i)))
            (setq douban-music-channels
                  (cons
                   (cons (douban--make-sure-int (cdr (assoc 'channel_id var)))
                         (cdr (assoc 'name var)))
                   douban-music-channels))))
        (setq douban-music-channels
              (sort douban-music-channels
                    (lambda (el1 el2)
                      (< (car el1) (car el2)))))))))

(defun douban-music-get-song-list-async (callback)
  "Get channels from douban music server, async version"
  (let* ((url (if douban-music-channels
                  (format douban-music-get-song-list-url douban-music-current-channel)
                (error "douban-music-current-channel is nil"))))
    (douban-music-send-url url nil callback)))

(defun douban-music-get-song-list (&optional async-json-buffer)
  "Get channels from douban music server"
  (let* ((url (if douban-music-current-channel
                  (format douban-music-get-song-list-url douban-music-current-channel)
                (error "douban-music-current-channel is nil")))
         (json-buffer (or async-json-buffer (douban-music-send-url url)))
         jason-start
         json-end
         jason)
    (with-current-buffer json-buffer
      (goto-char (point-min))
      (if (not (search-forward "song" nil t))
          (message "get song list failed")
        (setq json-start (line-beginning-position))
        (setq json-end (line-end-position))
        (setq json (cdr (assoc 'song (json-read-from-string
                                      (decode-coding-string
                                       (buffer-substring-no-properties json-start json-end)
                                       'utf-8)))))
        (cond ((not (vectorp json))
               (error "Invalid data format"))
              ((= (length json) 0)
               (setq json douban-music-song-json))
              (t (setq douban-music-song-json json)))
        (setq douban-music-song-list nil)
        (setq douban-music-current-song 0)
        (dotimes (i (length json))
          (let ((var (aref json i)))
            (setq douban-music-song-list
                  (cons var douban-music-song-list))))))))

(defun douban-music-interface-update ()
  (with-current-buffer douban-music-buffer-name
    (setq buffer-read-only nil)
    (erase-buffer)
    (insert (concat (propertize "豆瓣"
                                'face '(:height 1.3 :foreground "Grey70"))
                    (propertize "FM"
                                'face '(:height 1.4 :foreground "ForestGreen"))
                    (propertize " douban.fm\n\n"
                                'face '(:height 0.8 :foreground "grey70" :))))
    (insert (propertize "Channels:"
                        'face '(:foreground "Green3" :height 1.1)))
    (insert (propertize (format "\n%s%s"
                                douban-music-indent0
                                douban-music-channels-delimiter)
                        'face '(:foreground "Grey80")))
    (let (channels
          (counter 0)
          (channel-list douban-music-channels))
      (while channel-list
        (if (zerop (mod counter 7))
            (progn
              (if (not (zerop counter))
                  (insert channels))
              (setq channels (format "\n%s" douban-music-indent0))))
        (setq channels (concat channels (concat (propertize (format "%-3d" (caar channel-list))
                                                            'face '(:foreground "Green"))
                                                (propertize (format "%-10s " (cdar channel-list))
                                                            'face '(:foreground "Grey80")))))
        (setq counter (1+ counter))
        (setq channel-list (cdr channel-list)))
      (if (not (string-equal channels (format "\n%s" douban-music-indent0)))
          (insert channels))
      (insert (propertize (format "\n%s%s\n\n"
                                  douban-music-indent0
                                  douban-music-channels-delimiter)
                          'face '(:foreground "Grey80"))))
    (let (song
          title
          album
          artist
          company
          public-time
          song-info)
      (setq song (elt douban-music-song-list douban-music-current-song))
      (if song
          (progn
            (insert douban-music-indent2)
	    (if douban-music-local-icon
		(progn
		  (douban-music-insert-image douban-music-local-icon)
		  (insert douban-music-local-icon))
	      (douban-music-download-and-insert-image-async (aget song 'picture) (current-buffer) (point))))
        (error "current song is nil"))
      (insert (concat (propertize (format "\n\n%sCurrent song: "
                                          douban-music-indent0)
                                  'face 'douban-music-track-face)
                      (propertize (format "%s (kbps %s)"
                                          (aget (elt douban-music-song-list douban-music-current-song) 'title)
                                          (aget (elt douban-music-song-list douban-music-current-song) 'kbps))
                                  'face 'douban-music-publish-year-face)))
      (insert (concat (propertize (format "\n%sCurrent channel: "
                                          douban-music-indent0)
                                  'face 'douban-music-track-face)
                      (propertize (format "%s\n"
                                          (cdr (assoc douban-music-current-channel douban-music-channels)))
                                  'face 'douban-music-publish-year-face)))
      (dotimes (i (length douban-music-song-list))
        (setq song (elt douban-music-song-list i))
        (setq title (aget song 'title))
        (setq album (aget song 'albumtitle))
        (setq artist (aget song 'artist))
        (setq company (aget song 'company))
        (setq public-time (aget song 'public_time))
        (setq song-info (concat (propertize (format "\n%sTrack%2d " douban-music-indent1 i)
                                            'face 'douban-music-track-face)
                                (propertize "Title: " 'face 'douban-music-tag-face)
                                (propertize (format "%s\n" title) 'face 'douban-music-title-face)
                                (propertize (format "%sAlbum: "
                                                    douban-music-indent4)
                                            'face 'douban-music-tag-face)
                                (propertize (format "%s\n" album)
                                            'face 'douban-music-album-face)
                                (propertize (format "%sArtist: "
                                                    douban-music-indent4)
                                            'face 'douban-music-tag-face)
                                (propertize (format "%s\n" artist)
                                            'face 'douban-music-artist-face)
                                (propertize (format "%sCompany: "
                                                    douban-music-indent4)
                                            'face 'douban-music-tag-face)
                                (propertize (format "%s\n" company)
                                            'face 'douban-music-company-face)
                                (propertize (format "%sPublish Year: "
                                                    douban-music-indent4)
                                            'face 'douban-music-tag-face)
                                (propertize (format "%s" public-time)
                                            'face 'douban-music-publish-year-face)))
        (insert song-info)))
    (set-buffer-modified-p nil)
    (setq buffer-read-only t)
    (goto-char (point-min))
    (search-forward (format "Track%2d" douban-music-current-song))
    (goto-char (line-end-position))))

(defun douban-music-send-url (url &optional args callback)
  "Fetch data from douban music server."
  (let* ((url-request-method "GET")
	 (url-request-data (if args
			       (mapconcat (lambda (arg)
					    (concat (url-hexify-string (car arg))
						    "="
						    (url-hexify-string (cdr arg))))
					  args "&")
			     url-request-data)))
    (if callback
        (url-retrieve url callback)
      (url-retrieve-synchronously url))))

(defun douban-music-insert-image (image-file)
  "Insert image file into text buffer."
  (let ((buffer-read-only nil))
    (when image-file
      (condition-case err
	  (let ((img (progn
		       (clear-image-cache image-file)
		       (create-image image-file nil nil :relief 2 :ascent 'center))))
	    (insert-image img)
	    img)
	(error
	 (when (file-exists-p image-file)
	   (delete-file image-file))
	 nil)))))

(defun download-image-callback (status &rest arg)
  (let ((douban-buffer (car arg))
        (point (cadr arg))
        (image-file (concat douban-music-cache-directory
			    douban-music-image-file)))
    (setq buffer-file-coding-system 'no-conversion)
    (goto-char (point-min))
    (let ((end (search-forward "\n\n" nil t)))
      (when end
	(delete-region (point-min) end)
	(write-region (point-min) (point-max) image-file nil 0)))
    (kill-buffer)
    (with-current-buffer douban-buffer
      (save-excursion
          (goto-char point)
          (douban-music-insert-image image-file)))
    (run-hooks 'douban-song-info-complete-hook)))


(defun douban-music-download-and-insert-image-async (url douban-buffer point)
    (url-retrieve url #'download-image-callback (list douban-buffer point)))

;;;###autoload
(defun douban-music ()
  "Play douban music in its own buffer."
  (interactive)
  (cond
   ((and douban-music-alive (buffer-live-p (get-buffer douban-music-buffer-name)))
    (switch-to-buffer douban-music-buffer-name))
   (t
    (if (not (file-exists-p douban-music-cache-directory))
        (mkdir douban-music-cache-directory t))
    (set-buffer (get-buffer-create douban-music-buffer-name))
    (douban-music-mode)
    (if (and (not (string-match "mplayer" douban-music-player))
             (not (string-match "mpg123" douban-music-player)))
        (error "Unknown player"))
    (douban-music-get-channels)
    (setq douban-music-current-channel douban-music-default-channel)
    (douban-music-get-song-list)
    (douban-music-kill-process)
    (douban-music-play)
    (setq douban-music-alive t)
    (set-buffer-modified-p nil)
    (select-window (display-buffer (current-buffer)))
    (delete-other-windows))))

(defun douban-music-mode ()
  "Major mode for controlling the Douban Music buffer.

This buffer used to show douban music play under emacs."
  (kill-all-local-variables)
  (use-local-map douban-music-mode-map)
  (setq major-mode 'douban-music-mode)
  (setq mode-name "Douban-Music")
  (setq truncate-lines t)
  (setq buffer-read-only t)
  (setq buffer-undo-list t)
  (run-hooks 'douban-music-mode-hook))

;;; provide features
(provide 'douban-music-mode)

;;; douban-music-mode.el ends here
