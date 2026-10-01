package com.example.face3d;

import android.net.Uri;
import android.os.Bundle;
import android.widget.*;
import androidx.activity.result.ActivityResultLauncher;
import androidx.activity.result.contract.ActivityResultContracts;
import androidx.appcompat.app.AppCompatActivity;

public class MainActivity extends AppCompatActivity {
    private ImageView preview;
    private Button generate;
    private TextView status;
    private Uri selectedImage;

    @Override protected void onCreate(Bundle savedInstanceState) {
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
                    status.setText("Fotografie încărcată.");
                }
            });

        select.setOnClickListener(v -> picker.launch("image/*"));

        generate.setOnClickListener(v -> {
            status.setText("Modulul de reconstrucție 3D trebuie conectat.");
            Toast.makeText(this,
                "Proiect pregătit pentru integrarea reconstrucției 3D.",
                Toast.LENGTH_LONG).show();
        });
    }
}
