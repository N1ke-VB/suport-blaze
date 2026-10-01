package com.example.face3d;

import android.graphics.Bitmap;
import android.graphics.BitmapFactory;
import android.net.Uri;
import android.os.Bundle;
import android.widget.Button;
import android.widget.ImageView;
import android.widget.TextView;
import android.widget.Toast;

import androidx.activity.result.ActivityResultLauncher;
import androidx.activity.result.contract.ActivityResultContracts;
import androidx.appcompat.app.AppCompatActivity;

import java.io.BufferedWriter;
import java.io.File;
import java.io.FileInputStream;
import java.io.FileOutputStream;
import java.io.InputStream;
import java.io.OutputStream;
import java.io.OutputStreamWriter;
import java.nio.charset.StandardCharsets;
import java.text.SimpleDateFormat;
import java.util.Date;
import java.util.Locale;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

public class MainActivity extends AppCompatActivity {
    private ImageView preview;
    private Button generate;
    private TextView status;
    private Uri selectedImage;
    private File pendingModel;
    private final ExecutorService worker = Executors.newSingleThreadExecutor();

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        setContentView(R.layout.activity_main);

        preview = findViewById(R.id.preview);
        generate = findViewById(R.id.generateButton);
        status = findViewById(R.id.status);
        Button select = findViewById(R.id.selectButton);

        ActivityResultLauncher<String> picker =
                registerForActivityResult(new ActivityResultContracts.GetContent(), uri -> {
                    if (uri != null) {
                        selectedImage = uri;
                        preview.setImageURI(uri);
                        generate.setEnabled(true);
                        status.setText("Fotografie încărcată. Apasă Generează model 3D.");
                    }
                });

        ActivityResultLauncher<String> saveModel =
                registerForActivityResult(new ActivityResultContracts.CreateDocument("model/obj"), uri -> {
                    if (uri == null || pendingModel == null) return;
                    worker.execute(() -> {
                        try (InputStream in = new FileInputStream(pendingModel);
                             OutputStream out = getContentResolver().openOutputStream(uri)) {
                            if (out == null) throw new IllegalStateException("Nu pot deschide fișierul ales.");
                            byte[] buffer = new byte[8192];
                            int read;
                            while ((read = in.read(buffer)) != -1) out.write(buffer, 0, read);
                            out.flush();
                            runOnUiThread(() -> {
                                status.setText("Modelul 3D a fost salvat ca fișier OBJ.");
                                Toast.makeText(this, "Model 3D salvat.", Toast.LENGTH_LONG).show();
                            });
                        } catch (Exception e) {
                            runOnUiThread(() -> status.setText("Eroare la salvare: " + e.getMessage()));
                        }
                    });
                });

        select.setOnClickListener(v -> picker.launch("image/*"));

        generate.setOnClickListener(v -> {
            if (selectedImage == null) return;
            generate.setEnabled(false);
            status.setText("Generez mesh-ul 3D offline...");

            worker.execute(() -> {
                try {
                    Bitmap bitmap = loadBitmap(selectedImage);
                    if (bitmap == null) throw new IllegalStateException("Imaginea nu a putut fi citită.");
                    pendingModel = createPhotoReliefObj(bitmap);
                    String fileName = "Face3D_" +
                            new SimpleDateFormat("yyyyMMdd_HHmmss", Locale.US).format(new Date()) + ".obj";
                    runOnUiThread(() -> {
                        generate.setEnabled(true);
                        status.setText("Mesh 3D generat. Alege unde vrei să salvezi fișierul OBJ.");
                        saveModel.launch(fileName);
                    });
                } catch (Exception e) {
                    runOnUiThread(() -> {
                        generate.setEnabled(true);
                        status.setText("Eroare: " + e.getMessage());
                    });
                }
            });
        });
    }

    private Bitmap loadBitmap(Uri uri) throws Exception {
        try (InputStream in = getContentResolver().openInputStream(uri)) {
            return BitmapFactory.decodeStream(in);
        }
    }

    private File createPhotoReliefObj(Bitmap source) throws Exception {
        int gridWidth = 64;
        float aspect = (float) source.getHeight() / (float) source.getWidth();
        int gridHeight = Math.max(40, Math.min(96, Math.round(gridWidth * aspect)));
        Bitmap small = Bitmap.createScaledBitmap(source, gridWidth, gridHeight, true);

        float[][] depth = new float[gridHeight][gridWidth];
        float[][] red = new float[gridHeight][gridWidth];
        float[][] green = new float[gridHeight][gridWidth];
        float[][] blue = new float[gridHeight][gridWidth];

        for (int y = 0; y < gridHeight; y++) {
            for (int x = 0; x < gridWidth; x++) {
                int c = small.getPixel(x, y);
                float r = ((c >> 16) & 255) / 255f;
                float g = ((c >> 8) & 255) / 255f;
                float b = (c & 255) / 255f;
                red[y][x] = r;
                green[y][x] = g;
                blue[y][x] = b;

                float luminance = 0.2126f * r + 0.7152f * g + 0.0722f * b;
                float nx = (x / (float) (gridWidth - 1)) * 2f - 1f;
                float ny = (y / (float) (gridHeight - 1)) * 2f - 1f;
                float centerBulge = Math.max(0f, 1f - (nx * nx * 0.72f + ny * ny * 0.55f));
                depth[y][x] = 0.02f + centerBulge * 0.25f + (luminance - 0.5f) * 0.16f;
            }
        }

        for (int pass = 0; pass < 3; pass++) {
            float[][] smooth = new float[gridHeight][gridWidth];
            for (int y = 0; y < gridHeight; y++) {
                for (int x = 0; x < gridWidth; x++) {
                    float sum = 0f;
                    int count = 0;
                    for (int yy = Math.max(0, y - 1); yy <= Math.min(gridHeight - 1, y + 1); yy++) {
                        for (int xx = Math.max(0, x - 1); xx <= Math.min(gridWidth - 1, x + 1); xx++) {
                            sum += depth[yy][xx];
                            count++;
                        }
                    }
                    smooth[y][x] = sum / count;
                }
            }
            depth = smooth;
        }

        File out = new File(getCacheDir(), "face3d_model.obj");
        try (BufferedWriter w = new BufferedWriter(new OutputStreamWriter(
                new FileOutputStream(out), StandardCharsets.UTF_8))) {
            w.write("# Face 3D Creator - offline photo relief\n");
            w.write("# Vertex format: v x y z r g b (RGB extension supported by many OBJ viewers)\n");
            w.write("o Face3DPhotoRelief\n");

            float meshAspect = gridHeight / (float) gridWidth;
            for (int y = 0; y < gridHeight; y++) {
                for (int x = 0; x < gridWidth; x++) {
                    float vx = (x / (float) (gridWidth - 1) - 0.5f) * 2f;
                    float vy = (0.5f - y / (float) (gridHeight - 1)) * 2f * meshAspect;
                    float vz = depth[y][x];
                    w.write(String.format(Locale.US,
                            "v %.6f %.6f %.6f %.5f %.5f %.5f\n",
                            vx, vy, vz, red[y][x], green[y][x], blue[y][x]));
                }
            }

            for (int y = 0; y < gridHeight - 1; y++) {
                for (int x = 0; x < gridWidth - 1; x++) {
                    int a = y * gridWidth + x + 1;
                    int b = a + 1;
                    int c = a + gridWidth;
                    int d = c + 1;
                    w.write("f " + a + " " + c + " " + b + "\n");
                    w.write("f " + b + " " + c + " " + d + "\n");
                }
            }
        }

        small.recycle();
        return out;
    }

    @Override
    protected void onDestroy() {
        worker.shutdownNow();
        super.onDestroy();
    }
}
