Shader "Custom/DisneyPBR"
{
    Properties
    {
        _AlbedoTex ("Texture", 2D) = "white" {}
        _NormalMap ("Normal Map", 2D) = "bump" {}
        _MetallicSmoothMap("MetallicSmoothMap", 2D) = "white" {}
    }
    SubShader
    {
        Tags { "RenderType"="Opaque" "RenderPipeline"="UniversalRenderPipeline" }
        
        Pass
        {
            Name "UnlitPass"
            Tags { "LightMode" = "UniversalForward" }

            HLSLPROGRAM
            #pragma vertex VSMain
            #pragma fragment PSMain
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Input.hlsl"
            
            struct VSInput
            {
                float4 pos : POSITION;
                float2 uv : TEXCOORD0;
                float3 normal : NORMAL;
                float4 tangent : TANGENT;
            };

            struct VSOutput
            {
                float4 pos : SV_POSITION;
                float2 uv : TEXCOORD0;
                float3 worldPos : TEXCOORD1;
                float3 normalWS : NORMAL;
                float3 tangentWS : TEXCOORD2;
                float3 bitangentWS : TEXCOORD3;
                float3 normalInView : TEXCOORD4;
            };
            
            CBUFFER_START(UnityPerMaterial)
            TEXTURE2D (_AlbedoTex);
            SAMPLER(sampler_AlbedoTex);
            TEXTURE2D(_NormalMap);
            SAMPLER(sampler_NormalMap);
            TEXTURE2D(_MetallicSmoothMap);
            SAMPLER(sampler_MetallicSmoothMap);
            CBUFFER_END

            float3 GetNormal(float3 normal, float3 tangent, float3 biNormal, float2 uv)
            {
                float3 binSpaceNormal = UnpackNormal(SAMPLE_TEXTURE2D(_NormalMap, sampler_NormalMap, uv));

                float3 newNormal = tangent * binSpaceNormal.x + biNormal * binSpaceNormal.y + normal * binSpaceNormal.z;

                return newNormal;
            }

            float Beckmann(float m, float t)
            {
                float t2 =  t * t;
                float t4 = t2 * t2;
                float m2 = m * m;
                float D = 1.0f / (4.0f * m2 * t4);
                D *= exp((-1.0f / m2) * (1.0f - t2) / t2);
                return D;
            }

            float SpcFresnel(float f0, float u)
            {
                return f0 + (1.0f - f0) * pow(1.0f - u, 5.0f);
            }
            
            float CookTorranceSpecular(float3 L, float3 V, float3 N, float metallic)
            {
                float microfacet = 0.76f;

                float f0 = metallic;

                float3 H = normalize(L + V);

                float NdotH = saturate(dot(N, H));
                float VdotH = saturate(dot(V, H));
                float NdotL = saturate(dot(N, L));
                float NdotV = saturate(dot(N, V));

                float D = Beckmann(microfacet, NdotH);
                float F = SpcFresnel(f0, VdotH);
                float G = min(1.0f, min((2.0f * NdotH * NdotV) / VdotH, (2.0f * NdotH * NdotL) / VdotH));
                float m = PI * NdotV * NdotH;
                return max(F * D * G / m, 0.0f);
            }
            
            VSOutput VSMain(VSInput In)
            {
                VSOutput vsOut;
                
                vsOut.pos = TransformObjectToHClip(In.pos);
                vsOut.worldPos = TransformObjectToWorld(In.pos);
                vsOut.uv =  In.uv;

                vsOut.normalWS = TransformObjectToWorldNormal(In.normal);
                vsOut.tangentWS = TransformObjectToWorldDir(In.tangent.xyz);
                vsOut.bitangentWS = cross(vsOut.normalWS, vsOut.tangentWS) * In.tangent.w;

                vsOut.normalInView = TransformWorldToViewNormal(TransformObjectToWorldNormal(In.normal));
                
                return vsOut;
            }

            float CalcDiffuseFromFresnel(float3 N, float3 L, float3 V)
            {
                float dotNL = saturate(dot(N, L));
                float dotNV = saturate(dot(N, V));
                return (dotNL*dotNV);
            }
            
            float4 PSMain(VSOutput vsOut) : SV_Target0
            {
                float3 normal = GetNormal(vsOut.normalWS, vsOut.tangentWS, vsOut.bitangentWS, vsOut.uv);

                float4 albedoColor = SAMPLE_TEXTURE2D(_AlbedoTex, sampler_AlbedoTex, vsOut.uv);

                float3 specColor = albedoColor;

                float metallic = SAMPLE_TEXTURE2D(_MetallicSmoothMap, sampler_MetallicSmoothMap, vsOut.uv).r;
                float smooth = SAMPLE_TEXTURE2D(_MetallicSmoothMap, sampler_MetallicSmoothMap, vsOut.uv).a;

                float3 eyePos = GetCameraPositionWS();
                float3 toEye = normalize(eyePos - vsOut.worldPos);
                
                Light mainLight = GetMainLight();
                float3 mainLigDirection = mainLight.direction;
                float dijffuseFromFresnel = CalcDiffuseFromFresnel(normal, mainLigDirection, toEye);

                
                float NdotL = saturate(dot(normal, mainLigDirection));
                float3 lambertDiffuse = mainLight.color * NdotL/PI;

                float3 diffuse = albedoColor * dijffuseFromFresnel * lambertDiffuse;

                float3 spec = CookTorranceSpecular(mainLigDirection, toEye, normal, 1.0f - smooth) * mainLight.color;

                spec *= lerp(float3(1.0f, 1.0f, 1.0f), specColor, metallic);
                
                float3 lig = diffuse * (1.0f - smooth) + spec;

                float3 ambientLight = 0.3f;
                lig += ambientLight * albedoColor;

                float4 finalColor = 1.0f;
                finalColor.xyz = lig;
                return finalColor;
            }
            
            ENDHLSL
        }
    }
}
