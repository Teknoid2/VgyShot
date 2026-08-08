#!/bin/bash

# ==============================================================================
# INSTALLATEUR POUR VGYSHOT
# ==============================================================================
# Cet installateur configure vGyShot, gère les dépendances système
# et s'occupe de l'intégration au bureau.
# ==============================================================================

# Couleurs pour le terminal
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # Pas de couleur

# Titre
echo -e "${CYAN}"
echo "================================================================"
echo "  __      __  ____  __   __ ____  _   _  ___  _____ "
echo "  \ \    / / / ___| \ \ / // ___|| | | |/ _ \|_   _| "
echo "   \ \  / / | |  _   \ V / \___ \| |_| | | | | | |   "
echo "    \ \/ /  | |_| |   | |   ___) |  _  | |_| | | |   "
echo "     \__/    \____|   |_|  |____/|_| |_|\___/  |_|  "
echo "================================================================"
echo -e "${NC}"

# 1. Choix du type d'installation
REAL_USER="${SUDO_USER:-$USER}"
REAL_HOME=$(getent passwd "$REAL_USER" | cut -d: -f6)
if [ "$EUID" -eq 0 ]; then
    SUDO=""
else
    SUDO="sudo"
fi

echo -e "${BLUE}[1/6] Dossier de destination${NC}"
TARGET_DIR="/usr/local/bin"
DESKTOP_DIR="/usr/share/applications"
USE_SUDO=true
echo -e "Destination d'installation : ${GREEN}/usr/local/bin${NC} (Système)"

# 2. Vérification et installation des dépendances
echo ""
echo -e "${BLUE}[2/6] Vérification des dépendances système${NC}"
dependencies=(yad maim slop xdotool xclip jq curl ffmpeg imagemagick python3 python3-pil)
missing_deps=()

for dep in "${dependencies[@]}"; do
    if [ "$dep" = "python3-pil" ]; then
        if ! python3 -c "from PIL import Image" &>/dev/null; then
            missing_deps+=("python3-pil")
        fi
    elif [ "$dep" = "imagemagick" ]; then
        if ! command -v convert &>/dev/null; then
            missing_deps+=("imagemagick")
        fi
    else
        if ! command -v "$dep" &>/dev/null; then
            missing_deps+=("$dep")
        fi
    fi
done

if [ ${#missing_deps[@]} -ne 0 ]; then
    echo -e "${YELLOW}Dépendances manquantes détectées : ${missing_deps[*]}${NC}"
    echo "Souhaitez-vous les installer automatiquement via apt ?"
    read -rp "Installer les dépendances ? (O/n) : " INSTALL_DEPS
    INSTALL_DEPS=${INSTALL_DEPS:-O}
    
    if [[ "$INSTALL_DEPS" =~ ^[OoYy]$ ]]; then
        echo -e "${YELLOW}Mise à jour des paquets et installation...${NC}"
        $SUDO apt update
        $SUDO apt install -y "${missing_deps[@]}"
        if [ $? -eq 0 ]; then
            echo -e "${GREEN}Toutes les dépendances ont été installées avec succès !${NC}"
        else
            echo -e "${RED}Erreur lors de l'installation des dépendances. Veuillez les installer manuellement.${NC}"
            exit 1
        fi
    else
        echo -e "${RED}Installation annulée. vGyShot nécessite ces dépendances pour fonctionner.${NC}"
        exit 1
    fi
else
    echo -e "${GREEN}Toutes les dépendances requises sont déjà installées !${NC}"
fi

# 3. Création du script vGyShot
echo ""
echo -e "${BLUE}[3/6] Déploiement de vGyShot${NC}"

TEMP_FILE=$(mktemp)

cat << 'EOF' > "$TEMP_FILE"
#!/bin/bash

# ==============================================================================
# CONFIGURATION
# ==============================================================================
CONFIG_DIR="$HOME/.config/vgyshot"
CONFIG_FILE_JSON="$CONFIG_DIR/config.json"
DEFAULT_API_KEY=""
TARGET_DIR="$HOME/Images/Capture d'écran"
HEADER_CROP_HEIGHT=235

mkdir -p "$TARGET_DIR"
mkdir -p "$CONFIG_DIR"

# Fonction robuste pour charger les configurations
load_config() {
    API_KEY="$DEFAULT_API_KEY"
    STREAMABLE_EMAIL=""
    STREAMABLE_PASSWORD=""
    AUDIO_SOURCE="none"

    if [ -f "$CONFIG_FILE_JSON" ]; then
        API_KEY=$(jq -r '.api_key // ""' "$CONFIG_FILE_JSON")
        STREAMABLE_EMAIL=$(jq -r '.streamable_email // ""' "$CONFIG_FILE_JSON")
        STREAMABLE_PASSWORD=$(jq -r '.streamable_password // ""' "$CONFIG_FILE_JSON")
        AUDIO_SOURCE=$(jq -r '.audio_source // "none"' "$CONFIG_FILE_JSON")
    else
        # Rétrocompatibilité avec l'ancien fichier de config plat s'il existe
        CONFIG_FILE_OLD="$CONFIG_DIR/config"
        if [ -f "$CONFIG_FILE_OLD" ]; then
            while IFS='=' read -r key value; do
                # Supprimer les quotes autour de la valeur
                value="${value%\"}"
                value="${value#\"}"
                if [ "$key" = "API_KEY" ]; then
                    API_KEY="$value"
                elif [ "$key" = "STREAMABLE_EMAIL" ]; then
                    STREAMABLE_EMAIL="$value"
                elif [ "$key" = "STREAMABLE_PASSWORD" ]; then
                    STREAMABLE_PASSWORD="$value"
                fi
            done < "$CONFIG_FILE_OLD" 2>/dev/null
        fi
        
        # Créer le nouveau fichier JSON
        jq -n \
           --arg ak "$API_KEY" \
           --arg se "$STREAMABLE_EMAIL" \
           --arg sp "$STREAMABLE_PASSWORD" \
           --arg as "$AUDIO_SOURCE" \
           '{api_key: $ak, streamable_email: $se, streamable_password: $sp, audio_source: $as, first_run: true}' > "$CONFIG_FILE_JSON"
    fi
}

load_config

# 🔍 Vérification des dépendances système critiques au démarrage
if ! command -v convert &> /dev/null || ! command -v slop &> /dev/null || ! command -v xdotool &> /dev/null; then
    notify-send "vGyShot ⚠️" "Dépendances manquantes. Installez imagemagick, slop et xdotool." --icon=dialog-warning
fi

# ==============================================================================
# FONCTION DE CAPTURE ET UPLOAD
# ==============================================================================
capture_and_upload() {
    # Recharger les configurations
    load_config
    MODE=$1
    RANDOM_STR=$(tr -dc 'A-Za-z' < /dev/urandom | head -c 9)

    if [ "$MODE" = "region" ]; then
        sleep 0.2
        FILE_NAME="temporary_capture_${RANDOM_STR}.png"
        FILE_PATH="$TARGET_DIR/$FILE_NAME"
        maim -s "$FILE_PATH"
        
        if [ ! -s "$FILE_PATH" ]; then
            notify-send "vGyShot" "Capture annulée." --icon=dialog-information
            [ -f "$FILE_PATH" ] && rm "$FILE_PATH"
            return
        fi
        
        WINDOW_ID=$(xdotool getmouselocation --shell 2>/dev/null | grep WINDOW | cut -d= -f2)
        if [ -n "$WINDOW_ID" ]; then
            APP_NAME=$(xprop -id "$WINDOW_ID" WM_CLASS 2>/dev/null | awk -F '"' '{print $2}' | tr '[:upper:]' '[:lower:]')
        fi

    elif [ "$MODE" = "window" ]; then
        sleep 0.2
        FILE_NAME="temporary_capture_${RANDOM_STR}.png"
        FILE_PATH="$TARGET_DIR/$FILE_NAME"
        # Utiliser la sélection de fenêtre native de maim
        maim -s -t 9999999 "$FILE_PATH"
        
        if [ ! -s "$FILE_PATH" ]; then
            notify-send "vGyShot" "Capture annulée." --icon=dialog-information
            [ -f "$FILE_PATH" ] && rm "$FILE_PATH"
            return
        fi
        
        WINDOW_ID=$(xdotool getmouselocation --shell 2>/dev/null | grep WINDOW | cut -d= -f2)
        if [ -n "$WINDOW_ID" ]; then
            APP_NAME=$(xprop -id "$WINDOW_ID" WM_CLASS 2>/dev/null | awk -F '"' '{print $2}' | tr '[:upper:]' '[:lower:]')
        fi

    elif [ "$MODE" = "scroll" ]; then
        notify-send "vGyShot 📜" "Sélectionnez LA FENÊTRE ENTIÈRE de votre navigateur." --icon=dialog-information
        sleep 0.6
        
        GEO=$(slop -f "%wx%h+%x+%y" 2>/dev/null)
        if [ -z "$GEO" ]; then
            notify-send "vGyShot" "Capture défilante annulée." --icon=dialog-information
            return
        fi

        IFS='x+' read -r W H X Y <<< "$GEO"
        
        # Save current mouse position
        eval $(xdotool getmouselocation --shell)
        ORIG_X=$X
        ORIG_Y=$Y
        
        # Click the title bar area to focus the window first without clicking inside the webpage
        CLICK_X=$((X + W / 2))
        CLICK_Y=$((Y + 15))
        xdotool mousemove "$CLICK_X" "$CLICK_Y" click 1 mousemove "$ORIG_X" "$ORIG_Y"
        sleep 0.3
        
        WINDOW_ID=$(xdotool getactivewindow 2>/dev/null)
        
        SAFE_ZONE_X=$((X + W / 2))
        SAFE_ZONE_Y=$((Y + H / 2))
        
        if [ -n "$WINDOW_ID" ]; then
            APP_NAME=$(xprop -id "$WINDOW_ID" WM_CLASS 2>/dev/null | awk -F '"' '{print $2}' | tr '[:upper:]' '[:lower:]')
        fi
        
        SCROLL_TMP_DIR="/tmp/vgyshot_scroll_${RANDOM_STR}"
        mkdir -p "$SCROLL_TMP_DIR"
        
        notify-send "vGyShot" "Capture en cours... Laissez le script travailler." --icon=media-record
        
        FILE_NAME="temporary_capture_${RANDOM_STR}.png"
        FILE_PATH="$TARGET_DIR/$FILE_NAME"
        
        # Calculate the Y offset of the selection relative to the window top
        Y_OFFSET=0
        if [ -n "$WINDOW_ID" ]; then
            eval $(xdotool getwindowgeometry --shell "$WINDOW_ID" 2>/dev/null | sed "s/^/WIN_/")
            if [ -n "$WIN_Y" ]; then
                Y_OFFSET=$(( Y - WIN_Y ))
            fi
        fi
        export Y_OFFSET
        
        python3 - "$SCROLL_TMP_DIR" "$FILE_PATH" "$GEO" "$WINDOW_ID" "$SAFE_ZONE_X" "$SAFE_ZONE_Y" > /tmp/vgyshot_stitcher.log 2>&1 << 'EOF_PYTHON'
import os
import sys
import glob
import time
import subprocess
from PIL import Image, ImageChops, ImageStat

def detect_webpage_viewport(img1, img2):
    """
    Detects the webpage rendering area viewport within the captured window by comparing row differences.
    Chrome/Firefox UI elements at the top (tabs, bookmarks) and bottom (borders, statusbar) are static,
    while the webpage content changes after scrolling.
    """
    W, H = img1.size
    x0, x1 = int(W * 0.3), int(W * 0.7)
    crop_w = x1 - x0
    if crop_w < 10:
        return 0, H
        
    img1_cropped = img1.crop((x0, 0, x1, H))
    img2_cropped = img2.crop((x0, 0, x1, H))
    
    downsample_width = min(128, crop_w)
    small1 = img1_cropped.resize((downsample_width, H), Image.Resampling.BILINEAR).convert('L')
    small2 = img2_cropped.resize((downsample_width, H), Image.Resampling.BILINEAR).convert('L')
    
    pixels1 = list(small1.getdata())
    pixels2 = list(small2.getdata())
    
    row_diffs = []
    for y in range(H):
        diff = sum(abs(pixels1[y * downsample_width + x] - pixels2[y * downsample_width + x]) for x in range(downsample_width)) / float(downsample_width)
        row_diffs.append(diff)
        
    y_top = 0
    threshold = 5.0
    for y in range(H):
        if row_diffs[y] > threshold:
            y_top = y
            break
            
    y_bottom = H
    for y in range(H - 1, -1, -1):
        if row_diffs[y] > threshold:
            y_bottom = y + 1
            break
            
    if y_bottom - y_top < H * 0.3:
        return 0, H
        
    return y_top, y_bottom

def detect_header_height(img1, img2, default_fallback=235):
    """
    Detects the static header height by comparing img1 and img2 row-by-row.
    Looks for the boundary using a sliding average to handle solid/repetitive backgrounds robustly.
    """
    W, H = img1.size
    # Exclude left and right margins (30% on each side) to avoid scrollbar/side noise & notifications
    x0, x1 = int(W * 0.3), int(W * 0.7)
    crop_w = x1 - x0
    if crop_w < 10:
        x0, x1 = 0, W
        crop_w = W
        
    img1_cropped = img1.crop((x0, 0, x1, H))
    img2_cropped = img2.crop((x0, 0, x1, H))
    
    # Downsample to width 128 for robust row-by-row comparison
    downsample_width = min(128, crop_w)
    small1 = img1_cropped.resize((downsample_width, H), Image.Resampling.BILINEAR).convert('L')
    small2 = img2_cropped.resize((downsample_width, H), Image.Resampling.BILINEAR).convert('L')
    
    pixels1 = list(small1.getdata())
    pixels2 = list(small2.getdata())
    
    # Calculate row-by-row differences
    row_diffs = []
    for y in range(H):
        diff = sum(abs(pixels1[y * downsample_width + x] - pixels2[y * downsample_width + x]) for x in range(downsample_width)) / float(downsample_width)
        row_diffs.append(diff)
        
    # Find the boundary using a sliding window of 15 rows
    window_size = 15
    max_header_pct = 0.45  # Header shouldn't occupy more than 45% of the window
    max_search_y = int(H * max_header_pct)
    
    threshold = 15.0
    header_height = 0
    
    # Check if the first window already shows significant differences (i.e. no header)
    first_window_avg = sum(row_diffs[:window_size]) / float(window_size)
    if first_window_avg > threshold:
        # Search the first window for the exact transition row
        for i in range(window_size):
            if row_diffs[i] > threshold:
                print(f"[Stitcher] First window shows significant difference at row {i}. Assuming NO static header.")
                return i
        print(f"[Stitcher] First window shows significant difference average ({first_window_avg:.2f} > {threshold}). Assuming NO static header.")
        return 0
        
    for y in range(max_search_y - window_size):
        window_avg = sum(row_diffs[y : y + window_size]) / float(window_size)
        if window_avg > threshold:
            # Search the window for the exact transition row where the diff jumps
            for i in range(y, y + window_size):
                if row_diffs[i] > threshold:
                    header_height = i
                    break
            else:
                header_height = y
            break
            
    print(f"[Stitcher] Dynamically detected header height: {header_height}px")
    return header_height

def check_if_identical(img1, img2, header_height):
    """
    Checks if img1 and img2 viewports are virtually identical (excluding margins).
    Returns the MAE (Mean Absolute Error).
    """
    W, H = img1.size
    x0, x1 = int(W * 0.3), int(W * 0.7)
    if x1 - x0 < 10:
        x0, x1 = 0, W
        
    # Crop to the viewport
    viewport1 = img1.crop((x0, header_height, x1, H)).convert('L')
    viewport2 = img2.crop((x0, header_height, x1, H)).convert('L')
    
    diff = ImageChops.difference(viewport1, viewport2)
    stat = ImageStat.Stat(diff)
    
    # Total pixels
    total_pixels = viewport1.width * viewport1.height
    if total_pixels == 0:
        return 0.0
        
    mae = stat.sum[0] / float(total_pixels)
    return mae

def find_best_stitch_y(canvas, next_img, header_height, dw=512):
    """
    Finds the best Y coordinate in the canvas to stitch the next image.
    Uses the entire-overlap matching algorithm for 100% accuracy on periodic lists.
    """
    W, H = next_img.size
    viewport_height = H - header_height
    
    # Exclude left and right margins (20% on each side) to avoid scrollbar/side noise & notifications
    x0, x1 = int(W * 0.2), int(W * 0.8)
    crop_w = x1 - x0
    if crop_w < 10:
        x0, x1 = 0, W
        crop_w = W
        
    # Crop the horizontal content region of both images
    canvas_cropped = canvas.crop((x0, 0, x1, canvas.height))
    next_cropped = next_img.crop((x0, 0, x1, H))
    
    # Resize width but KEEP height intact for exact vertical resolution!
    target_dw = min(dw, crop_w)
    canvas_small = canvas_cropped.resize((target_dw, canvas.height), Image.Resampling.BILINEAR).convert('L')
    next_small = next_cropped.resize((target_dw, H), Image.Resampling.BILINEAR).convert('L')
    
    max_ov_h = min(canvas.height, H - header_height)
    best_ov_h = 30
    min_diff_val = float('inf')
    
    # Search overlap height from 30 to max_ov_h
    for ov_h in range(30, max_ov_h + 1):
        c_crop = canvas_small.crop((0, canvas.height - ov_h, target_dw, canvas.height))
        n_crop = next_small.crop((0, header_height, target_dw, header_height + ov_h))
        
        diff = ImageChops.difference(c_crop, n_crop)
        stat = ImageStat.Stat(diff)
        diff_val = stat.sum[0] / float(target_dw * ov_h)  # MAE per pixel
        
        if diff_val < min_diff_val:
            min_diff_val = diff_val
            best_ov_h = ov_h
            
    # Calculate stitch_y using best_ov_h
    actual_stitch_y = canvas.height - best_ov_h
    return actual_stitch_y, min_diff_val

def capture_screenshot(geo, output_path, hide_cursor=False):
    cmd = ["maim"]
    if hide_cursor:
        cmd.append("-u")
    cmd.extend(["-g", geo, output_path])
    subprocess.run(cmd, check=True)

def scroll_page(window_id):
    subprocess.run(["xdotool", "windowactivate", "--sync", str(window_id)], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    subprocess.run(["xdotool", "windowfocus", "--sync", str(window_id)], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    # Scroll down one page
    subprocess.run(["xdotool", "key", "Page_Down"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    time.sleep(0.5)
    # Scroll back up slightly to ensure a large overlap
    subprocess.run(["xdotool", "key", "--delay", "60", "--repeat", "6", "Up"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    time.sleep(0.5)

def capture_and_stitch(temp_dir, output_path, geo, window_id, safe_zone_x, safe_zone_y, default_fallback=235):
    y_offset = int(os.environ.get('Y_OFFSET', '0'))
    images = []
    header_height_map = {}
    successful_scrolls = []
    y_top = 0
    y_bottom = None
    browser_ui_height = 0
    viewport_detected = False
    
    # Focus and activate
    print(f"[Stitcher] Activating window {window_id}...")
    subprocess.run(["xdotool", "windowactivate", "--sync", str(window_id)], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    subprocess.run(["xdotool", "windowfocus", "--sync", str(window_id)], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    time.sleep(0.5)
        
    max_parts = 25
    for idx in range(1, max_parts + 1):
        current_part = os.path.join(temp_dir, f"part_{idx:02d}.png")
        print(f"[Stitcher] Capturing part {idx}/{max_parts}...")
        
        try:
            capture_screenshot(geo, current_part, hide_cursor=(idx > 1))
        except Exception as e:
            print(f"[Stitcher] Error during capture: {e}")
            break
            
        img = Image.open(current_part)
        if viewport_detected:
            img = img.crop((0, y_top, img.width, y_bottom))
            
        images.append((current_part, img))
        
        if idx >= 2 and not viewport_detected:
            # Check if there was any scroll between the last two raw images
            prev_img = images[-2][1]
            curr_img = images[-1][1]
            mae = check_if_identical(prev_img, curr_img, 0)
            print(f"[Stitcher] MAE between raw frames {idx-1} and {idx}: {mae:.4f}")
            if mae >= 1.5:
                # Page scrolled! Detect viewport boundaries
                det_top, det_bottom = detect_webpage_viewport(prev_img, curr_img)
                viewport_height = det_bottom - det_top
                window_height = prev_img.height
                if viewport_height >= window_height * 0.55:
                    y_top, y_bottom = det_top, det_bottom
                    viewport_detected = True
                    browser_ui_height = y_top
                    print(f"[Stitcher] Auto-detected webpage viewport: y_top={y_top}px, y_bottom={y_bottom}px")
                    print(f"[Stitcher] Selection Y offset: {y_offset}px. Using browser UI height for first frame crop: {browser_ui_height}px")
                    
                    # Retrospectively crop the already captured images
                    images[0] = (images[0][0], images[0][1].crop((0, browser_ui_height, images[0][1].width, y_bottom)))
                    for k in range(1, len(images)):
                        images[k] = (images[k][0], images[k][1].crop((0, y_top, images[k][1].width, y_bottom)))
        
        if idx > 1:
            if not viewport_detected:
                # Viewport has not been detected yet (identical frames so far)
                mae = check_if_identical(images[-2][1], images[-1][1], 0)
                if mae < 1.2:
                    print("[Stitcher] Viewport unchanged (no scroll detected yet). Retrying focus and scroll...")
                    scroll_page(window_id)
                    time.sleep(1.0)
                    os.remove(current_part)
                    images.pop()
                    try:
                        capture_screenshot(geo, current_part, hide_cursor=True)
                        img = Image.open(current_part)
                        images.append((current_part, img))
                    except Exception as e:
                        print(f"[Stitcher] Error during retry capture: {e}")
                        break
                    
                    mae = check_if_identical(images[-2][1], images[-1][1], 0)
                    if mae < 1.2:
                        print("[Stitcher] Confirmed bottom of page / not scrollable (no scroll detected after retry).")
                        break
            else:
                # Normal capture loop stop detection and stitching offsets (when scrolling is active)
                viewport_mae = check_if_identical(images[-2][1], images[-1][1], 0)
                print(f"[Stitcher] Direct viewport similarity MAE: {viewport_mae:.4f}")
                if viewport_mae < 1.2:
                    print("[Stitcher] Viewport unchanged. Retrying focus and scroll...")
                    scroll_page(window_id)
                    time.sleep(1.0)
                    os.remove(current_part)
                    images.pop()
                    
                    try:
                        capture_screenshot(geo, current_part, hide_cursor=True)
                    except Exception as e:
                        print(f"[Stitcher] Error during retry capture: {e}")
                        break
                    img = Image.open(current_part)
                    img = img.crop((0, y_top, img.width, y_bottom))
                    images.append((current_part, img))
                    
                    viewport_mae = check_if_identical(images[-2][1], images[-1][1], 0)
                    print(f"[Stitcher] Post-retry viewport similarity MAE: {viewport_mae:.4f}")
                    if viewport_mae < 1.2:
                        print(f"[Stitcher] Confirmed bottom of page (viewport similarity MAE {viewport_mae:.4f} < 1.2).")
                        print("[Stitcher] Performing final absolute bottom capture...")
                        subprocess.run(["xdotool", "windowactivate", "--sync", str(window_id)], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
                        subprocess.run(["xdotool", "windowfocus", "--sync", str(window_id)], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
                        subprocess.run(["xdotool", "key", "End"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
                        time.sleep(1.0)
                        try:
                            capture_screenshot(geo, current_part, hide_cursor=True)
                            img = Image.open(current_part)
                            img = img.crop((0, y_top, img.width, y_bottom))
                            images[-1] = (current_part, img)
                        except Exception as e:
                            print(f"[Stitcher] Error during final bottom capture: {e}")
                        break
                    
                # 2. Compare previous part and current part to check scroll distance
                stitch_y, match_score = find_best_stitch_y(images[-2][1], images[-1][1], 0)
                scroll_dist = stitch_y - (y_top - browser_ui_height) if idx == 2 else stitch_y
                print(f"[Stitcher] Step scroll distance: {scroll_dist}px (match score: {match_score:.2f})")
                
                if match_score <= 25.0:
                    successful_scrolls.append(scroll_dist)
                    
                if scroll_dist < 10:
                    print(f"[Stitcher] Low scroll distance ({scroll_dist}px). Retrying focus and scroll...")
                    scroll_page(window_id)
                    time.sleep(1.0)
                    os.remove(current_part)
                    images.pop()
                    
                    try:
                        capture_screenshot(geo, current_part, hide_cursor=True)
                    except Exception as e:
                        print(f"[Stitcher] Error during retry capture: {e}")
                        break
                    img = Image.open(current_part)
                    img = img.crop((0, y_top, img.width, y_bottom))
                    images.append((current_part, img))
                    
                    stitch_y, match_score = find_best_stitch_y(images[-2][1], images[-1][1], 0)
                    scroll_dist = stitch_y - (y_top - browser_ui_height) if idx == 2 else stitch_y
                    print(f"[Stitcher] Post-retry step scroll distance: {scroll_dist}px (match score: {match_score:.2f})")
                    if scroll_dist < 10:
                        print(f"[Stitcher] Confirmed bottom of page (scroll distance {scroll_dist}px < 10px).")
                        print("[Stitcher] Performing final absolute bottom capture...")
                        subprocess.run(["xdotool", "windowactivate", "--sync", str(window_id)], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
                        subprocess.run(["xdotool", "windowfocus", "--sync", str(window_id)], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
                        subprocess.run(["xdotool", "key", "End"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
                        time.sleep(1.0)
                        try:
                            capture_screenshot(geo, current_part, hide_cursor=True)
                            img = Image.open(current_part)
                            img = img.crop((0, y_top, img.width, y_bottom))
                            images[-1] = (current_part, img)
                        except Exception as e:
                            print(f"[Stitcher] Error during final bottom capture: {e}")
                        break
                
        # Scroll down for next part
        scroll_page(window_id)
        time.sleep(1.0)
        
    if not images:
        print("[Stitcher] Error: No images captured.")
        sys.exit(1)
        
    if not viewport_detected:
        print("[Stitcher] Page did not scroll. Cropping browser UI from first frame and saving.")
        browser_ui_height = max(0, default_fallback - y_offset)
        canvas = images[0][1]
        browser_ui_height = min(canvas.height - 10, browser_ui_height)
        canvas_cropped = canvas.crop((0, browser_ui_height, canvas.width, canvas.height))
        canvas_cropped.save(output_path)
        return
        
    # Stitch everything
    print("[Stitcher] Stitching screenshots...")
    canvas = images[0][1]
    W, H = canvas.size
    
    # Calculate fallback scroll distance from successful scrolls
    if successful_scrolls:
        fallback_S = sum(successful_scrolls) / len(successful_scrolls)
        print(f"[Stitcher] Calculated fallback scroll distance from history: {fallback_S:.1f}px")
    else:
        fallback_S = H - 150
        print(f"[Stitcher] No history of successful scrolls. Using fallback scroll distance: {fallback_S:.1f}px")
        
    for idx in range(1, len(images)):
        next_path, next_img = images[idx]
        h_height = 0
        stitch_y, match_score = find_best_stitch_y(canvas, next_img, h_height)
        
        print(f"[Stitcher] Stitching image {idx+1}/{len(images)} at canvas Y={stitch_y} (score: {match_score:.2f})")
        if match_score > 25.0:
            # Match is poor.
            # Special-case the last frame (bottom of the page)
            if idx == len(images) - 1:
                print(f"[Stitcher] Warning: Poor match score on bottom frame. Prioritizing template matched best_S over large fallback scroll distance.")
            else:
                # Adjust stitch_y based on fallback_S.
                stitch_y = int(canvas.height - next_img.height + fallback_S)
                print(f"[Stitcher] Warning: Poor match score. Using fallback scroll distance. Adjusting canvas Y to {stitch_y}")
            
        canvas_cropped = canvas.crop((0, 0, canvas.width, stitch_y))
        next_cropped = next_img
        
        new_canvas = Image.new('RGB', (canvas.width, canvas_cropped.height + next_cropped.height))
        new_canvas.paste(canvas_cropped, (0, 0))
        new_canvas.paste(next_cropped, (0, canvas_cropped.height))
        print(f"[Stitcher] Step {idx}: canvas_cropped height={canvas_cropped.height}, next_cropped height={next_cropped.height}, new_canvas size={new_canvas.size}")
        new_canvas.save(f"/tmp/vgyshot_canvas_step{idx}.png")
        canvas = new_canvas
        
    print(f"[Stitcher] Final canvas size before saving: {canvas.size}")
    canvas.save(output_path)
    print(f"[Stitcher] Successfully saved stitched capture to: {output_path}")
    # Double check file on disk immediately after saving
    try:
        chk = Image.open(output_path)
        print(f"[Stitcher] Verified saved file on disk size: {chk.size}")
    except Exception as e:
        print(f"[Stitcher] Error verifying saved file on disk: {e}")

if __name__ == "__main__":
    temp_dir = sys.argv[1]
    output_path = sys.argv[2]
    geo = sys.argv[3]
    window_id = sys.argv[4]
    safe_zone_x = int(sys.argv[5])
    safe_zone_y = int(sys.argv[6])
    default_fallback = int(os.environ.get('HEADER_CROP_HEIGHT', '235'))
    
    capture_and_stitch(temp_dir, output_path, geo, window_id, safe_zone_x, safe_zone_y, default_fallback=default_fallback)
EOF_PYTHON
        
        # Keep temporary files for debugging
        echo "[Stitcher] Kept temporary files in $SCROLL_TMP_DIR"

    else
        sleep 0.5
        WINDOW_ID=$(xdotool getactivewindow 2>/dev/null)
        if [ -n "$WINDOW_ID" ]; then
            APP_NAME=$(xprop -id "$WINDOW_ID" WM_CLASS 2>/dev/null | awk -F '"' '{print $2}' | tr '[:upper:]' '[:lower:]')
        fi
        
        FILE_NAME="temporary_capture_${RANDOM_STR}.png"
        FILE_PATH="$TARGET_DIR/$FILE_NAME"
        maim "$FILE_PATH"
        
        if [ ! -s "$FILE_PATH" ]; then
            notify-send "vGyShot" "Capture annulée." --icon=dialog-information
            [ -f "$FILE_PATH" ] && rm "$FILE_PATH"
            return
        fi
    fi
    
    if [ "$APP_NAME" = "cinnamon" ] || [ -z "$APP_NAME" ]; then
        APP_NAME="capture"
    fi

    FINAL_NAME="${APP_NAME}_${RANDOM_STR}.png"
    FINAL_PATH="$TARGET_DIR/$FINAL_NAME"
    mv "$FILE_PATH" "$FINAL_PATH"

    notify-send "vGyShot" "📸 Sauvegardé : $FINAL_NAME\nTéléversement vers vgy.me..." --icon=camera

    RESPONSE=$(curl -s -F "userkey=$API_KEY" -F "file=@$FINAL_PATH" https://vgy.me/upload)
    ERROR=$(echo "$RESPONSE" | jq -r '.error')
    URL=$(echo "$RESPONSE" | jq -r '.image')

    if [ "$ERROR" = "false" ] && [ "$URL" != "null" ]; then
        echo -n "$URL" | xclip -selection clipboard
        notify-send "vGyShot - Succès 🎉" "Lien copié dans le presse-papiers !\n$URL" --icon=emblem-success
    else
        notify-send "vGyShot - Échec ❌" "Erreur d'upload. Dispo dans Images/Capture d'écran." --icon=dialog-error
    fi
}

configure_settings() {
    # Charger les configurations actuelles
    load_config
    
    # Préparer les options pour la liste déroulante YAD
    OPT_NONE="Aucun (pas de son)"
    OPT_MIC="Microphone (par défaut)"
    OPT_SYS="Son système (desktop)"
    OPT_BOTH="Microphone + Son système"
    
    case "$AUDIO_SOURCE" in
        mic)    AUDIO_LIST="^$OPT_MIC!$OPT_NONE!$OPT_SYS!$OPT_BOTH" ;;
        system) AUDIO_LIST="^$OPT_SYS!$OPT_NONE!$OPT_MIC!$OPT_BOTH" ;;
        both)   AUDIO_LIST="^$OPT_BOTH!$OPT_NONE!$OPT_MIC!$OPT_SYS" ;;
        *)      AUDIO_LIST="^$OPT_NONE!$OPT_MIC!$OPT_SYS!$OPT_BOTH" ;;
    esac
    
    # Ouvrir le formulaire de configuration unifié
    FORM_OUTPUT=$(yad --form --title="vGyShot - Configuration" \
        --field="Clé API vgy.me" \
        --field="Email Streamable" \
        --field="Mot de passe Streamable":H \
        --field="Source Audio":CB \
        "$API_KEY" "$STREAMABLE_EMAIL" "$STREAMABLE_PASSWORD" "$AUDIO_LIST" \
        --width=450 --button="Enregistrer:0" --button="Annuler:1" 2>/dev/null)
        
    if [ $? -eq 0 ] && [ -n "$FORM_OUTPUT" ]; then
        # Extraire les valeurs
        IFS='|' read -r NEW_API_KEY NEW_EMAIL NEW_PASS NEW_AUDIO _ <<< "$FORM_OUTPUT"
        
        case "$NEW_AUDIO" in
            "$OPT_MIC")  NEW_AUDIO_SRC="mic" ;;
            "$OPT_SYS")  NEW_AUDIO_SRC="system" ;;
            "$OPT_BOTH") NEW_AUDIO_SRC="both" ;;
            *)           NEW_AUDIO_SRC="none" ;;
        esac
        
        # Sauvegarder dans le fichier de config JSON de manière sécurisée
        jq -n \
           --arg ak "$NEW_API_KEY" \
           --arg se "$NEW_EMAIL" \
           --arg sp "$NEW_PASS" \
           --arg as "$NEW_AUDIO_SRC" \
           '{api_key: $ak, streamable_email: $se, streamable_password: $sp, audio_source: $as}' > "$CONFIG_FILE_JSON"
        
        load_config
        
        notify-send "vGyShot - Configuration" "Paramètres sauvegardés avec succès ! 🎉" --icon=emblem-success
    fi
}

record_and_upload_video() {
    # Recharger les configurations
    load_config
    
    # Sélectionner la zone à enregistrer
    GEO=$(slop -f "%x %y %w %h" 2>/dev/null)
    if [ -z "$GEO" ]; then
        notify-send "vGyShot" "Enregistrement annulé." --icon=dialog-information
        return
    fi
    
    # Parser la géométrie
    read -r X Y W H <<< "$GEO"
    
    # Forcer W et H à être pairs (ffmpeg x214 requiert des dimensions paires pour yuv420p)
    W=$(( W - (W % 2) ))
    H=$(( H - (H % 2) ))
    
    RANDOM_STR=$(tr -dc 'A-Za-z' < /dev/urandom | head -c 9)
    VIDEO_NAME="capture_video_${RANDOM_STR}.mp4"
    VIDEO_PATH="$TARGET_DIR/$VIDEO_NAME"
    
    # Configuration dynamique de l'audio ffmpeg
    FFMPEG_AUDIO_ARGS=()
    if [ "$AUDIO_SOURCE" = "mic" ]; then
        MIC_SRC=$(pactl get-default-source 2>/dev/null || echo "default")
        FFMPEG_AUDIO_ARGS=(-f pulse -i "$MIC_SRC" -map 0:v -map 1:a -c:a aac)
    elif [ "$AUDIO_SOURCE" = "system" ]; then
        SYS_SRC="$(pactl get-default-sink 2>/dev/null).monitor"
        FFMPEG_AUDIO_ARGS=(-f pulse -i "$SYS_SRC" -map 0:v -map 1:a -c:a aac)
    elif [ "$AUDIO_SOURCE" = "both" ]; then
        MIC_SRC=$(pactl get-default-source 2>/dev/null || echo "default")
        SYS_SRC="$(pactl get-default-sink 2>/dev/null).monitor"
        FFMPEG_AUDIO_ARGS=(-f pulse -i "$MIC_SRC" -f pulse -i "$SYS_SRC" -filter_complex "[1:a][2:a]amix=inputs=2[a]" -map 0:v -map "[a]" -c:a aac)
    else
        FFMPEG_AUDIO_ARGS=(-an)
    fi
    
    notify-send "vGyShot" "🎥 Démarrage de l'enregistrement de la zone ${W}x${H}..." --icon=media-record
    
    # Lancer ffmpeg en arrière-plan pour capturer l'écran et l'audio
    ffmpeg -f x11grab \
           -video_size "${W}x${H}" \
           -framerate 25 \
           -i "${DISPLAY}+${X},${Y}" \
           "${FFMPEG_AUDIO_ARGS[@]}" \
           -c:v libx264 \
           -preset ultrafast \
           -crf 23 \
           -pix_fmt yuv420p \
           -y "$VIDEO_PATH" > /tmp/vgyshot_ffmpeg.log 2>&1 &
           
    FFMPEG_PID=$!
    
    # Déterminer la position de la fenêtre de contrôle (en bas à droite par défaut, ou évitement intelligent)
    read -r SCREEN_W SCREEN_H <<< $(xdotool getdisplaygeometry 2>/dev/null)
    [ -z "$SCREEN_W" ] && SCREEN_W=1920
    [ -z "$SCREEN_H" ] && SCREEN_H=1080
    
    # Déterminer les coordonnées des 4 coins possibles (taille dialog: 180x60)
    X_BR=$(( SCREEN_W - 220 ))
    Y_BR=$(( SCREEN_H - 140 ))
    
    X_BG=40
    Y_BG=$(( SCREEN_H - 140 ))
    
    X_HD=$(( SCREEN_W - 220 ))
    Y_HD=40
    
    X_HG=40
    Y_HG=40
    
    check_overlap() {
        local cx=$1
        local cy=$2
        if (( cx < X + W && cx + 180 > X && cy < Y + H && cy + 60 > Y )); then
            return 0 # Chevauchement
        fi
        return 1 # Pas de chevauchement
    }
    
    if ! check_overlap $X_BR $Y_BR; then
        CTRL_X=$X_BR
        CTRL_Y=$Y_BR
    elif ! check_overlap $X_BG $Y_BG; then
        CTRL_X=$X_BG
        CTRL_Y=$Y_BG
    elif ! check_overlap $X_HD $Y_HD; then
        CTRL_X=$X_HD
        CTRL_Y=$Y_HD
    elif ! check_overlap $X_HG $Y_HG; then
        CTRL_X=$X_HG
        CTRL_Y=$Y_HG
    else
        CTRL_X=$X_BR
        CTRL_Y=$Y_BR
    fi
    
    CSS_PATH="/tmp/yad_video_timer_${RANDOM_STR}.css"
    cat << 'EOF_CSS' > "$CSS_PATH"
#yad-dialog-window, window, dialog {
    background-color: #1a1a1a;
    background-image: none;
    border: 1px solid #ff3333;
}
box, grid {
    background-color: #1a1a1a;
    background-image: none;
}
button, button label {
    background-color: #ff3333;
    background-image: none;
    color: #ffffff;
    border-radius: 4px;
}
button:hover, button:hover label {
    background-color: #cc0000;
    background-image: none;
}
label {
    color: #ffffff;
    font-size: 14px;
    font-weight: bold;
}
EOF_CSS

    # Afficher la boîte de dialogue avec timer et bouton d'arrêt rouge
    (
        SEC=0
        while kill -0 $FFMPEG_PID 2>/dev/null; do
            MIN=$(( SEC / 60 ))
            S=$(( SEC % 60 ))
            printf "# Enregistrement : %02d:%02d\n" $MIN $S
            echo $SEC
            sleep 1
            SEC=$(( SEC + 1 ))
        done
    ) | yad --progress \
            --geometry=180x60+${CTRL_X}+${CTRL_Y} \
            --undecorated \
            --on-top \
            --skip-taskbar \
            --gtkrc="$CSS_PATH" \
            --button="Arrêter:0" 2>/dev/null
        
    rm -f "$CSS_PATH"
        
    # Arrêter ffmpeg proprement en lui envoyant SIGINT (2) pour finaliser le fichier MP4
    kill -2 $FFMPEG_PID
    wait $FFMPEG_PID 2>/dev/null
    
    if [ ! -s "$VIDEO_PATH" ]; then
        notify-send "vGyShot - Vidéo ❌" "Erreur : fichier vidéo vide ou non généré." --icon=dialog-error
        return
    fi
    
    # Déterminer si on utilise Streamable (compte renseigné)
    if [ -n "$STREAMABLE_EMAIL" ] && [ -n "$STREAMABLE_PASSWORD" ]; then
        notify-send "vGyShot - Streamable 🚀" "Enregistrement terminé. Téléversement vers Streamable..." --icon=document-send
        
        # Téléverser vers Streamable
        RESPONSE=$(curl -s -u "$STREAMABLE_EMAIL:$STREAMABLE_PASSWORD" \
                        -F "file=@$VIDEO_PATH" \
                        https://api.streamable.com/upload)
                        
        SHORTCODE=$(echo "$RESPONSE" | jq -r '.shortcode' 2>/dev/null)
        
        if [ -n "$SHORTCODE" ] && [ "$SHORTCODE" != "null" ]; then
            URL="https://streamable.com/$SHORTCODE"
            echo -n "$URL" | xclip -selection clipboard
            notify-send "vGyShot - Streamable 🎉" "Lien vidéo copié dans le presse-papiers !\n$URL" --icon=emblem-success
        else
            ERROR_MSG=$(echo "$RESPONSE" | jq -r '.message' 2>/dev/null)
            if [ -n "$ERROR_MSG" ] && [ "$ERROR_MSG" != "null" ]; then
                notify-send "vGyShot - Streamable ❌" "Échec : $ERROR_MSG" --icon=dialog-error
            else
                notify-send "vGyShot - Streamable ❌" "Échec du téléversement vers Streamable." --icon=dialog-error
            fi
        fi
    else
        notify-send "vGyShot - Vidéo 🎬" "Enregistrement terminé et sauvegardé localement :\n$VIDEO_NAME" --icon=video-x-generic
    fi
}

check_first_run() {
    FIRST_RUN=$(jq -r '.first_run // "false"' "$CONFIG_FILE_JSON")
    if [ "$FIRST_RUN" = "true" ]; then
        yad --image="dialog-information" \
            --title="vGyShot - Premier démarrage" \
            --text="<b>Bienvenue dans vGyShot !</b>\n\nPour pouvoir utiliser pleinement l'application (téléversement d'images et de vidéos), vous devez renseigner :\n  • Votre <b>clé API vgy.me</b> (pour les images)\n  • Vos <b>identifiants streamable.com</b> (pour les vidéos)\n\nFaites un clic droit sur l'icône de notification (dans la barre d'état) et choisissez <b>⚙️ Configurer vGyShot</b> pour les renseigner." \
            --button="D'accord:0" \
            --width=450 \
            --center 2>/dev/null
            
        # Mettre à jour le fichier pour désactiver le flag au prochain démarrage
        jq '.first_run = false' "$CONFIG_FILE_JSON" > "${CONFIG_FILE_JSON}.tmp" && mv "${CONFIG_FILE_JSON}.tmp" "$CONFIG_FILE_JSON"
    fi
}

open_target_dir() {
    xdg-open "$TARGET_DIR"
}

export -f capture_and_upload configure_settings record_and_upload_video load_config open_target_dir check_first_run
export API_KEY TARGET_DIR HEADER_CROP_HEIGHT CONFIG_DIR CONFIG_FILE_JSON STREAMABLE_EMAIL STREAMABLE_PASSWORD AUDIO_SOURCE

MENU_OPTIONS="📸 Capturer une zone de l'écran!$0 region|🪟 Capturer une fenêtre!$0 window|🖥️ Capturer l'écran complet!$0 screen|📜 Capturer en défilement (Bas)!$0 scroll|🎥 Enregistrer une vidéo!$0 video|📂 Ouvrir le dossier des captures!$0 open|⚙️ Configurer vGyShot!$0 config|❌ Quitter vGyShot!quit"

if [ -n "$1" ]; then
    case "$1" in
        region|window|screen|scroll)
            capture_and_upload "$1"
            ;;
        video)
            record_and_upload_video
            ;;
        config)
            configure_settings
            ;;
        open)
            open_target_dir
            ;;
        *)
            echo "Usage: $0 {region|window|screen|scroll|video|config|open}"
            exit 1
            ;;
    esac
    exit 0
fi

check_first_run

PIPE=$(mktemp -u --tmpdir vgyshot.XXXXXX)
mkfifo "$PIPE"
exec 3<>"$PIPE"
trap "rm -f $PIPE" EXIT

yad --notification \
    --listen \
    --image="camera" \
    --text="vGyShot : Clic gauche = Zone | Clic droit = Menu" \
    --command="$0 region" \
    --menu="$MENU_OPTIONS" <&3
EOF

# Déplacer le fichier temporaire vers la destination
if [ "$USE_SUDO" = true ]; then
    echo "Copie du script dans $TARGET_DIR/vgyshot (nécessite sudo)..."
    $SUDO mv "$TEMP_FILE" "$TARGET_DIR/vgyshot"
    $SUDO chmod 755 "$TARGET_DIR/vgyshot"
else
    echo "Copie du script dans $TARGET_DIR/vgyshot..."
    mv "$TEMP_FILE" "$TARGET_DIR/vgyshot"
    chmod 755 "$TARGET_DIR/vgyshot"
fi

echo -e "${GREEN}Le script vGyShot a été déployé dans $TARGET_DIR/vgyshot !${NC}"

# 4. Intégration au Bureau (.desktop)
echo ""
echo -e "${BLUE}[4/6] Intégration au menu des applications (Bureau)${NC}"

TEMP_DESKTOP=$(mktemp)

cat << EOF > "$TEMP_DESKTOP"
[Desktop Entry]
Version=1.0
Type=Application
Name=vGyShot
Comment=Outil de capture d'écran et de vidéo avec upload vgy.me/Streamable
Exec=$TARGET_DIR/vgyshot
Icon=camera
Terminal=false
Categories=Utility;Graphics;
StartupNotify=false
EOF

if [ "$USE_SUDO" = true ]; then
    $SUDO mv "$TEMP_DESKTOP" "$DESKTOP_DIR/vgyshot.desktop"
    $SUDO chmod 644 "$DESKTOP_DIR/vgyshot.desktop"
else
    mv "$TEMP_DESKTOP" "$DESKTOP_DIR/vgyshot.desktop"
    chmod 644 "$DESKTOP_DIR/vgyshot.desktop"
fi

echo -e "${GREEN}Fichier desktop créé dans $DESKTOP_DIR/vgyshot.desktop !${NC}"

# Raccourci sur le Bureau pour exécution directe
if [ -d "$REAL_HOME/Bureau" ]; then
    BUREAU_DIR="$REAL_HOME/Bureau"
    if [ "$USE_SUDO" = true ]; then
        $SUDO cp "$DESKTOP_DIR/vgyshot.desktop" "$BUREAU_DIR/vgyshot.desktop"
        $SUDO chown "$REAL_USER:$REAL_USER" "$BUREAU_DIR/vgyshot.desktop"
        $SUDO chmod 755 "$BUREAU_DIR/vgyshot.desktop"
        sudo -u "$REAL_USER" gio set "$BUREAU_DIR/vgyshot.desktop" "metadata::trusted" yes 2>/dev/null || true
    else
        cp "$DESKTOP_DIR/vgyshot.desktop" "$BUREAU_DIR/vgyshot.desktop"
        chmod 755 "$BUREAU_DIR/vgyshot.desktop"
        gio set "$BUREAU_DIR/vgyshot.desktop" "metadata::trusted" yes 2>/dev/null || true
    fi
    echo -e "${GREEN}Raccourci créé sur votre Bureau : $BUREAU_DIR/vgyshot.desktop${NC}"
fi

# 5. Option de démarrage automatique (Autostart)
echo ""
echo -e "${BLUE}[5/6] Démarrage automatique au lancement de la session${NC}"
read -rp "Souhaitez-vous que vGyShot se lance au démarrage de votre session ? (O/n) : " AUTOSTART
AUTOSTART=${AUTOSTART:-O}

if [[ "$AUTOSTART" =~ ^[OoYy]$ ]]; then
    AUTOSTART_DIR="$REAL_HOME/.config/autostart"
    mkdir -p "$AUTOSTART_DIR"
    cp "$DESKTOP_DIR/vgyshot.desktop" "$AUTOSTART_DIR/vgyshot.desktop"
    echo -e "${GREEN}vGyShot a été configuré pour se lancer automatiquement au démarrage de la session.${NC}"
else
    echo "Démarrage automatique non configuré."
fi

# 6. Nettoyage de la configuration existante
echo ""
echo -e "${BLUE}[6/6] Nettoyage et remise à zéro de la configuration${NC}"
CONFIG_FILE="$REAL_HOME/.config/vgyshot/config.json"

if [ -f "$CONFIG_FILE" ]; then
    echo "Un fichier de configuration existant a été détecté dans :"
    echo "  $CONFIG_FILE"
    echo -e "${YELLOW}Voulez-vous réinitialiser complètement cette configuration (vider clés API et identifiants Streamable) ?${NC}"
    read -rp "Réinitialiser la configuration ? (O/n) : " RESET_CONFIG
    RESET_CONFIG=${RESET_CONFIG:-O}
    
    if [[ "$RESET_CONFIG" =~ ^[OoYy]$ ]]; then
        # Sauvegarde
        cp "$CONFIG_FILE" "${CONFIG_FILE}.bak"
        echo -e "${YELLOW}Sauvegarde de la configuration actuelle créée dans : ${CONFIG_FILE}.bak${NC}"
        
        # Supprimer/sauvegarder l'ancienne configuration plate pour éviter la restauration automatique
        CONFIG_FILE_OLD="$REAL_HOME/.config/vgyshot/config"
        if [ -f "$CONFIG_FILE_OLD" ]; then
            mv "$CONFIG_FILE_OLD" "${CONFIG_FILE_OLD}.bak" 2>/dev/null
        fi
        
        # Écriture de la config vide
        cat << 'EOF' > "$CONFIG_FILE"
{
  "api_key": "",
  "streamable_email": "",
  "streamable_password": "",
  "audio_source": "none",
  "first_run": true
}
EOF
        echo -e "${GREEN}Configuration réinitialisée avec succès ! Les clés et identifiants sont totalement vides.${NC}"
    else
        echo "Configuration existante conservée."
    fi
else
    # Création d'une config vide
    mkdir -p "$(dirname "$CONFIG_FILE")"
    cat << 'EOF' > "$CONFIG_FILE"
{
  "api_key": "",
  "streamable_email": "",
  "streamable_password": "",
  "audio_source": "none",
  "first_run": true
}
EOF
    # Nettoyer l'ancienne configuration plate si elle existe
    CONFIG_FILE_OLD="$REAL_HOME/.config/vgyshot/config"
    [ -f "$CONFIG_FILE_OLD" ] && rm -f "$CONFIG_FILE_OLD"
    echo -e "${GREEN}Nouveau fichier de configuration vide créé avec succès.${NC}"
fi

echo ""
echo -e "${GREEN}======================================================================${NC}"
echo -e "${GREEN}                INSTALLATION DE VGYSHOT TERMINÉE !                    ${NC}"
echo -e "${GREEN}======================================================================${NC}"
echo "Vous pouvez lancer vGyShot :"
echo "1. En cherchant 'vGyShot' dans votre menu d'applications."
echo "2. En exécutant la commande : vgyshot"
echo "3. Depuis la barre d'état système au démarrage (clic gauche = capturer, clic droit = menu)."
echo ""
echo "Pour configurer vos propres clés API et comptes, lancez vGyShot,"
echo "faites un clic droit sur l'icône photo dans la zone de notification,"
echo "et choisissez '⚙️ Configurer vGyShot'."
echo "======================================================================"

# Démarrage automatique de vGyShot à la fin de l'installation
echo -e "${BLUE}Démarrage de vGyShot...${NC}"
if [ -z "$DBUS_SESSION_BUS_ADDRESS" ]; then
    DBUS_FILE=$(ls -t "$REAL_HOME/.dbus/session-bus/"* 2>/dev/null | head -n 1)
    if [ -f "$DBUS_FILE" ]; then
        DBUS_SESSION_BUS_ADDRESS=$(grep -oP "DBUS_SESSION_BUS_ADDRESS='\K[^']+" "$DBUS_FILE")
    fi
fi

if [ "$USE_SUDO" = true ]; then
    # Lancer en tant qu'utilisateur non-root pour l'affichage graphique
    sudo -u "$REAL_USER" DISPLAY="$DISPLAY" XAUTHORITY="$XAUTHORITY" DBUS_SESSION_BUS_ADDRESS="$DBUS_SESSION_BUS_ADDRESS" "$TARGET_DIR/vgyshot" &
else
    "$TARGET_DIR/vgyshot" &
fi
