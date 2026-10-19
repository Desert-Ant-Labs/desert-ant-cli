# Photos and video

Find, rank, and crop photos by what is in them and how they came out, group near-duplicates, and pick the frame of a video to use as its thumbnail.

```
da eye IMG_0056.jpeg
```

```
photo  keeper 0.27  aesthetic 0.76  cover 0.73  sharpness 0.89
sharp, cat, animal, keeper, pet, couch, furniture, himalayan
2 pets
```

The first line names the kind of image (photo, selfie, screenshot, photo of screen, document, receipt, and the rest) and four scores:

- `keeper`: how likely people are to keep a photo like this.
- `aesthetic`: how good the photo is as a photograph.
- `cover`: how well the photo works as a cover or a thumbnail.
- `sharpness`: the probability that a person calls the photo sharp.

Keeper, aesthetic, and cover are percentiles: an aesthetic of 0.76 scores higher than 76% of the photos Eye was calibrated on. The second line holds the tags that reach a confidence of 0.5, most confident first, and the third counts faces, closed eyes, and pets, and says when a photo is turned on its side.

Eye reads JPEG, HEIC, PNG, TIFF, and the other formats macOS opens, upright by their EXIF orientation. On Linux, ffmpeg reads the photos and video, libheif reads HEIC, and a crop of a HEIC photo is written as a JPEG. Eye is in closed beta, so set `HF_TOKEN` to a Hugging Face token with access to [desert-ant-labs/eye](https://huggingface.co/desert-ant-labs/eye) before the first run.

## Filters

```
da eye trip/ --has beach --not blurry,people
```

`--has` keeps the photos with every tag listed, `--not` drops the photos with any of them, and the command prints the paths that match, one per line. The paths go to stdout alone, so the result pipes into other tools:

```
da eye ~/Desktop --has screenshot --strict | while IFS= read -r f; do mv "$f" ~/Screenshots/; done
```

`--strict` counts a tag at a confidence of 0.9 instead of 0.5. Use `--strict` for anything that acts without asking, like moving or deleting files.

## Near-duplicates, the best shot, and rankings

```
da eye burst/ --duplicates
```

```
IMG_0146.jpg  keep
IMG_0145.jpg

IMG_0147.jpg  keep
IMG_0148.jpg
IMG_0149.jpg

2 groups of near-duplicates in 5 photos. 3 could go.
```

When every photo has a capture time in its EXIF, only photos taken within seconds of each other count as near-duplicates. The photo to keep in each group comes first, chosen the way `--best` chooses.

```
da eye burst/ --best
da eye trip/ --sort aesthetic --limit 10
da eye trip/ --similar-to IMG_3615.HEIC --limit 5
```

- `--best` prints the one photo to keep from the set: nobody's eyes closed, then the best faces, then the keeper score.
- `--sort` ranks by `aesthetic`, `keeper`, `cover`, `sharpness`, or any tag's confidence, such as `--sort dog`.
- `--similar-to` ranks by how alike each photo is to the one named. Near-duplicates score above 0.9.

Filters apply first, so `da eye trip/ --has mountain --not people --sort aesthetic --limit 5` ranks the landscapes alone. Each command asks one question: `--duplicates`, `--best`, `--sort`, and `--similar-to` don't combine.

## Crops

```
da eye IMG_0056.jpeg --crop 1:1
```

`--crop` writes Eye's best crop at that aspect beside the input, `IMG_0056_crop.jpeg`, in the input's format. The aspect is width to height, such as `1:1`, `4:5`, `16:9`, or `1.91`, and the crop matches that aspect exactly. `--output-dir thumbs/` puts the crops in another folder. With a filter or a question, `--crop` crops each photo the answer names: the matches, the keepers, the best shot, or the ranked photos.

## Video

```
da eye launch.mp4 --thumbnail --crop 16:9
```

```
screenshot  1 minute, 81 frames
reference, sharp, keeper, tablet computer, letter message, newspaper, poster
thumbnail  0:08  cover 0.97
launch_thumbnail.jpg
```

Eye looks at a frame every second, at most 100 frames over the video, and `--every 5` looks every 5s. The second line lists the tags that hold in at least a quarter of the frames. The thumbnail is the frame with the best cover score among the frames with no blur and nobody's eyes closed. `--thumbnail` writes that frame at full size as `launch_thumbnail.jpg`, and `--crop` crops the frame to an aspect.

`--has` on a video prints the stretches where every condition holds:

```
da eye launch.mp4 --has people
```

```
0:12 to 0:17  5.2s
0:34 to 0:46  12s
```

## Tags

Every tag has a confidence from 0 to 1, calibrated so the same two cutoffs work for every tag: 0.5 by default, 0.9 with `--strict`.

| Group | Tags |
| --- | --- |
| Photo type | `photo`, `selfie`, `screenshot`, `photo_of_screen`, `receipt`, `document`, `id_card`, `whiteboard`, `map`, `chart_or_slide`, `meme_or_graphic`, `illustration_or_art`, `shopping_reference`, `medical_reference`, `repair_reference`, `other`, and `reference` for any capture taken to remember something |
| Keep or delete | `keeper`, `forgettable`, `accidental`, `technical_flaw`, `unusable`, `bad_framing`, `bad_lighting`, `test_or_duplicate_shot`, `reference_photo`, `low_content` |
| Quality | `sharp`, `blurry` (the whole frame soft with no sharp subject), `bokeh` (a sharp subject against a soft background), `peak_moment`, `rotated` |
| People | `people`, `group_shot` (three or more faces), `portrait` (one main face), `smiling`, `eyes_closed`, `everyone_smiling`, `everyone_looking`, `candid` |
| Faces | `eyes_closed`, `smiling`, `looking_at_camera`, `looking_away`, `happy`, `surprised`, on each face |
| Sensitive | `sensitive` (any of these), `nsfw_explicit`, `nsfw_suggestive`, `blood_injury`, `medical_hospital`, `funeral`, `accident_disaster`, `violence_protest`, `weapon` |
| Scenes | 558 Open Images classes, such as `dog`, `beach`, `food`, `car`, `mountain` |

Write a tag with underscores in `--has`, `--not`, and `--sort`; the screen shows it with spaces. To list every tag Eye computes, run `da eye photo.jpg --all-tags --json | jq -r '.tags | keys[]'`.

## Speed

On an M4 Max, Eye read 15 full-size photos in 6.2s, model load included, and 81 frames of a video in 10.7s. `--parts` computes less: `photo` (the kind, scenes, keep or delete, sensitive, scores), `layout` (people and pet boxes, crops), `faces`, and `sharpness`. A tag whose part didn't run is left out, and `blurry` needs `photo`, `faces`, and `sharpness`.

## Limits

- The scores rank photos against each other. A low keeper score on one photo says little until you compare it with the rest of the set.
- `--duplicates`, `--best`, `--sort`, and `--similar-to` compare photos, and leave videos out.
- The JSON holds the tags that reach the cutoff. `--all-tags` adds every confidence, and `--embedding` adds the 512 numbers Eye compares photos with.
